import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:llm_llamacpp/src/bindings/llama_bindings.dart';
import 'package:llm_llamacpp/src/loader/loader.dart';
import 'package:llm_llamacpp/src/loader/native_library_path.dart';

/// Helper class for initializing the llama.cpp backend.
///
/// This consolidates the backend initialization logic that was previously
/// duplicated across multiple files. It handles dynamic backend loading
/// which is required when GGML_BACKEND_DL=ON (e.g., on Android where
/// backends are loaded as separate .so files).
class BackendInitializer {
  BackendInitializer._();

  /// Tracks whether backends have been initialized in this process.
  /// Native libraries are shared across isolates, so we only need to
  /// load backends once. Loading them multiple times can cause crashes.
  static bool _backendsInitialized = false;

  /// Initializes the llama.cpp backend with dynamic backend loading support.
  ///
  /// This method:
  /// 1. Loads the llama library
  /// 2. Creates LlamaBindings
  /// 3. Attempts to load all backends dynamically (if available) - only once per process
  /// 4. Initializes the backend
  ///
  /// Returns a tuple of (DynamicLibrary, LlamaBindings).
  static (ffi.DynamicLibrary, LlamaBindings) initializeBackend() {
    final lib = loadLlamaLibrary();
    final bindings = LlamaBindings(lib);

    // Load all backends before initializing
    // This is required for dynamic backend loading (GGML_BACKEND_DL=ON)
    // On Android with GGML_BACKEND_DL=ON, backends are loaded as separate .so files
    //
    // IMPORTANT: Only load backends once per process!
    // Native library state is shared across Dart isolates. If we load backends
    // multiple times (e.g., once in main isolate, once in inference isolate),
    // it can cause corruption and crashes.
    if (!_backendsInitialized) {
      // ignore: avoid_print
      print('[llm_llamacpp] Initializing backends (first time)...');
      loadBackends(lib);
      _backendsInitialized = true;
    } else {
      // ignore: avoid_print
      print('[llm_llamacpp] Backends already initialized, skipping...');
    }

    bindings.llama_backend_init();

    _logRegisteredBackends(lib);
    _logSystemInfo(bindings);

    return (lib, bindings);
  }

  /// Prints `llama_print_system_info()` so we can see what feature flags the
  /// loaded native library was compiled with. Useful when debugging FFI ABI
  /// mismatches or wrong CPU variant selection.
  static void _logSystemInfo(LlamaBindings bindings) {
    try {
      final infoPtr = bindings.llama_print_system_info();
      if (infoPtr.address == 0) {
        return;
      }
      final info = infoPtr.cast<Utf8>().toDartString();
      // ignore: avoid_print
      print('[llm_llamacpp] System info: $info');
    } catch (e) {
      // ignore: avoid_print
      print('[llm_llamacpp] Could not read system info: $e');
    }
  }

  /// Logs the list of backends ggml currently has registered. Useful to
  /// confirm which backends (CPU / Vulkan / etc.) actually came online.
  static void _logRegisteredBackends(ffi.DynamicLibrary lib) {
    try {
      final ggmlBackendRegCount = lib
          .lookupFunction<ffi.Size Function(), int Function()>(
            'ggml_backend_reg_count',
          );
      final ggmlBackendRegGet = lib
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Size),
            ffi.Pointer<ffi.Void> Function(int)
          >('ggml_backend_reg_get');
      final ggmlBackendRegName = lib
          .lookupFunction<
            ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Void>),
            ffi.Pointer<ffi.Char> Function(ffi.Pointer<ffi.Void>)
          >('ggml_backend_reg_name');

      final count = ggmlBackendRegCount();
      final names = <String>[];
      for (var i = 0; i < count; i++) {
        final reg = ggmlBackendRegGet(i);
        if (reg.address == 0) continue;
        final namePtr = ggmlBackendRegName(reg);
        if (namePtr.address == 0) continue;
        names.add(namePtr.cast<Utf8>().toDartString());
      }
      // ignore: avoid_print
      print('[llm_llamacpp] Registered backends ($count): ${names.join(', ')}');
    } catch (e) {
      // Older ggml builds may not expose these helpers. Not fatal.
      // ignore: avoid_print
      print('[llm_llamacpp] Could not enumerate registered backends: $e');
    }
  }

  /// Initializes the llama.cpp backend in an isolate (skips all backend loading).
  ///
  /// This should be used in inference isolates. The native backends are already
  /// loaded into the process's native memory space by the main isolate - they're
  /// shared across isolates. Trying to load them again causes corruption/crashes.
  ///
  /// This method:
  /// 1. Opens libllama.so directly (skips _loadAndroidDependencies which would preload backends)
  /// 2. Creates LlamaBindings
  /// 3. Initializes the backend (but does NOT reload backend .so files)
  ///
  /// Returns a tuple of (DynamicLibrary, LlamaBindings).
  static (ffi.DynamicLibrary, LlamaBindings) initializeBackendForIsolate() {
    // ignore: avoid_print
    print(
      '[llm_llamacpp] Initializing backend for isolate (minimal loading)...',
    );

    // On Android, don't call loadLlamaLibrary() because it calls _loadAndroidDependencies()
    // which would try to DynamicLibrary.open() all the CPU backends again.
    // Just open libllama.so directly - all dependencies are already loaded in native memory.
    ffi.DynamicLibrary lib;
    if (Platform.isAndroid) {
      lib = ffi.DynamicLibrary.open('libllama.so');
    } else {
      // On other platforms, use the standard loader
      lib = loadLlamaLibrary();
    }

    final bindings = LlamaBindings(lib);

    // Skip backend loading - backends are already loaded and registered in native memory
    // by the main isolate. Just call llama_backend_init() which is safe to call multiple times.
    bindings.llama_backend_init();

    return (lib, bindings);
  }

  /// Initializes backend loading on an already-loaded library and bindings.
  ///
  /// This is useful when you already have a library and bindings instance
  /// and just need to perform the backend loading step.
  ///
  /// On Android, this uses dladdr to get the native library directory path
  /// and passes it to ggml_backend_load_all_from_path(). This is required
  /// because ggml_backend_load_all() tries to access /proc/self/exe which
  /// is blocked by SELinux on Android.
  ///
  /// Returns true if backends were loaded successfully, false otherwise.
  static bool loadBackends(ffi.DynamicLibrary lib) {
    // Load all backends before initializing
    // This is required for dynamic backend loading (GGML_BACKEND_DL=ON)
    // On Android with GGML_BACKEND_DL=ON, backends are loaded as separate .so files

    // On Android, we must use ggml_backend_load_all_from_path with the actual
    // native library directory. Using ggml_backend_load_all() without a path
    // causes SELinux "avc: denied" errors because it tries to read /proc/self/exe.
    if (Platform.isAndroid) {
      return _loadBackendsAndroid(lib);
    }

    // On other platforms, try ggml_backend_load_all (simpler, no path needed)
    try {
      final ggmlBackendLoadAll = lib
          .lookupFunction<ffi.Void Function(), void Function()>(
            'ggml_backend_load_all',
          );
      ggmlBackendLoadAll();
      return true;
    } catch (e) {
      // Function not found - try path-based version
    }

    // Try ggml_backend_load_all_from_path with null (uses default paths)
    try {
      final ggmlBackendLoadAllFromPath = lib
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Char>),
            void Function(ffi.Pointer<ffi.Char>)
          >('ggml_backend_load_all_from_path');
      ggmlBackendLoadAllFromPath(ffi.Pointer.fromAddress(0));
      return true;
    } catch (e2) {
      // ignore: avoid_print
      print('[llm_llamacpp] Warning: Could not load backends dynamically: $e2');
      // ignore: avoid_print
      print(
        '[llm_llamacpp] This may cause model loading to fail if backends are not statically linked',
      );
      return false;
    }
  }

  /// Load backends on Android using the native library directory path.
  ///
  /// Android requires passing the actual native library directory to
  /// ggml_backend_load_all_from_path() because:
  /// 1. ggml_backend_load_all() tries to read /proc/self/exe
  /// 2. SELinux blocks untrusted apps from reading the root filesystem
  /// 3. This causes "no backends are loaded" errors
  ///
  /// If ggml_backend_load_all_from_path() doesn't work (which can happen due to
  /// std::filesystem issues on some Android versions), we fall back to manually
  /// loading each CPU backend .so file using ggml_backend_load().
  static bool _loadBackendsAndroid(ffi.DynamicLibrary lib) {
    // Get the native library directory using dladdr
    final nativeLibDir = getNativeLibraryDirectory(lib);

    if (nativeLibDir == null) {
      // ignore: avoid_print
      print(
        '[llm_llamacpp] WARNING: Could not determine native library directory on Android',
      );
      // ignore: avoid_print
      print(
        '[llm_llamacpp] Falling back to ggml_backend_load_all() which may fail due to SELinux',
      );

      // Try anyway - it might work on some devices
      try {
        final ggmlBackendLoadAll = lib
            .lookupFunction<ffi.Void Function(), void Function()>(
              'ggml_backend_load_all',
            );
        ggmlBackendLoadAll();
        // ignore: avoid_print
        print(
          '[llm_llamacpp] Called ggml_backend_load_all() - backends might be loaded',
        );
        return true;
      } catch (e) {
        // ignore: avoid_print
        print('[llm_llamacpp] ERROR: ggml_backend_load_all failed: $e');
        return false;
      }
    }

    // Try ggml_backend_load_all_from_path first
    try {
      final ggmlBackendLoadAllFromPath = lib
          .lookupFunction<
            ffi.Void Function(ffi.Pointer<ffi.Char>),
            void Function(ffi.Pointer<ffi.Char>)
          >('ggml_backend_load_all_from_path');

      // Convert the path to a native string
      final pathPtr = nativeLibDir.toNativeUtf8();
      try {
        ggmlBackendLoadAllFromPath(pathPtr.cast<ffi.Char>());
        // ignore: avoid_print
        print(
          '[llm_llamacpp] Called ggml_backend_load_all_from_path("$nativeLibDir")',
        );
      } finally {
        calloc.free(pathPtr);
      }
    } catch (e) {
      // ignore: avoid_print
      print('[llm_llamacpp] ggml_backend_load_all_from_path failed: $e');
    }

    // Patched: loading the same .so twice registers duplicate devices, which
    // makes llama.cpp pick broken kernels. Only fall back if nothing registered.
    final registered = _deviceCount(lib);
    // ignore: avoid_print
    print('[llm_llamacpp] Registered devices after load_all: $registered');
    if (registered > 0) {
      return true;
    }

    return _loadBackendsManually(lib, nativeLibDir);
  }

  static int _deviceCount(ffi.DynamicLibrary lib) {
    try {
      return lib
          .lookupFunction<ffi.Size Function(), int Function()>(
            'ggml_backend_dev_count',
          )
          .call();
    } catch (_) {
      return 0;
    }
  }

  /// Manually load backend .so files from the given directory.
  ///
  /// This is a fallback for when ggml_backend_load_all_from_path doesn't work
  /// (which can happen on Android due to std::filesystem issues).
  static bool _loadBackendsManually(
    ffi.DynamicLibrary lib,
    String nativeLibDir,
  ) {
    // ignore: avoid_print
    print(
      '[llm_llamacpp] Attempting manual backend loading from: $nativeLibDir',
    );

    // Get the ggml_backend_load function
    ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>) ggmlBackendLoad;
    try {
      ggmlBackendLoad = lib
          .lookupFunction<
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>),
            ffi.Pointer<ffi.Void> Function(ffi.Pointer<ffi.Char>)
          >('ggml_backend_load');
    } catch (e) {
      // ignore: avoid_print
      print('[llm_llamacpp] ERROR: ggml_backend_load not found: $e');
      return false;
    }

    // List the directory to find CPU backend .so files
    final dir = Directory(nativeLibDir);
    if (!dir.existsSync()) {
      // ignore: avoid_print
      print(
        '[llm_llamacpp] ERROR: Native library directory does not exist: $nativeLibDir',
      );
      return false;
    }

    int loadedCount = 0;

    bool load(String label, String fullPath) {
      final pathPtr = fullPath.toNativeUtf8();
      try {
        final result = ggmlBackendLoad(pathPtr.cast<ffi.Char>());
        if (result.address != 0) {
          // ignore: avoid_print
          print('[llm_llamacpp] Successfully loaded: $label');
          loadedCount++;
          return true;
        }
        // GPU backends may legitimately fail at runtime (e.g. Vulkan driver
        // missing). That's not fatal; the CPU backend keeps working.
        // ignore: avoid_print
        print('[llm_llamacpp] Failed to load: $label (returned null)');
        return false;
      } finally {
        calloc.free(pathPtr);
      }
    }

    try {
      final files = dir.listSync().whereType<File>().toList();
      // ignore: avoid_print
      print(
        '[llm_llamacpp] Found ${files.length} files in native lib directory',
      );

      final cpuBackends = <File>[];
      for (final entity in files) {
        final filename = entity.uri.pathSegments.last;
        if (!filename.startsWith('libggml-') || !filename.endsWith('.so')) {
          continue;
        }
        if (filename == 'libggml-base.so') continue;
        if (filename.startsWith('libggml-cpu')) {
          cpuBackends.add(entity);
        } else {
          load(filename, entity.path);
        }
      }

      // Only one CPU variant may be registered; prefer the most specific one.
      cpuBackends.sort(
        (a, b) => b.uri.pathSegments.last.compareTo(a.uri.pathSegments.last),
      );
      for (final entity in cpuBackends) {
        if (load(entity.uri.pathSegments.last, entity.path)) break;
      }
    } catch (e) {
      // ignore: avoid_print
      print('[llm_llamacpp] ERROR listing directory: $e');
      return false;
    }

    // ignore: avoid_print
    print('[llm_llamacpp] Manually loaded $loadedCount backend(s)');
    return loadedCount > 0;
  }
}
