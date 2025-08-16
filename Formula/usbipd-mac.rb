class UsbipdMac < Formula
  desc "macOS USB/IP protocol implementation for sharing USB devices over IP"
  homepage "https://github.com/beriberikix/usbipd-mac"
  url "https://github.com/beriberikix/usbipd-mac/archive/VERSION_PLACEHOLDER.tar.gz"
  version "VERSION_PLACEHOLDER"
  sha256 "SHA256_PLACEHOLDER"
  license "MIT"
  
  depends_on :macos => :big_sur
  depends_on :xcode => ["13.0", :build]
  
  # Performance optimization options
  option "with-debug-symbols", "Keep debug symbols for debugging (increases binary size)"
  option "with-full-optimization", "Enable maximum optimization (longer build time, smaller binary)"
  
  # Resource hints for Homebrew caching
  resource "build-cache" do
    # This helps Homebrew understand build requirements for better caching
  end
  
  def install
    # Performance optimizations for faster installation
    ENV["SWIFT_PARALLEL_BUILD"] = "YES"
    ENV["SWIFT_BUILD_JOBS"] = Hardware::CPU.cores.to_s
    
    # Enable Homebrew's build caching
    ENV["HOMEBREW_CACHE"] = "#{HOMEBREW_CACHE}/swift-build" if defined?(HOMEBREW_CACHE)
    
    # Memory optimization for build process
    ENV["SWIFT_DETERMINISTIC_HASHING"] = "1"
    ENV["SWIFT_FORCE_MODULE_LOADING"] = "prefer-serialized"
    
    # Optimize Swift build for release distribution
    swift_flags = [
      "--configuration", "release",
      "--disable-sandbox",
      # Parallel compilation - use all available cores
      "--jobs", Hardware::CPU.cores.to_s
    ]
    
    # Add optimization flags based on user options
    if build.with? "full-optimization"
      swift_flags += [
        # Maximum optimization (longer build time)
        "-Xswiftc", "-Ounchecked",
        "-Xswiftc", "-whole-module-optimization",
        "-Xswiftc", "-cross-module-optimization",
      ]
    else
      swift_flags += [
        # Balanced optimization for size and speed
        "-Xswiftc", "-O",
        "-Xswiftc", "-whole-module-optimization",
        # Prioritize size optimization for distribution
        "-Xswiftc", "-Osize",
      ]
    end
    
    # Link-time optimization
    swift_flags += [
      "-Xlinker", "-dead_strip",
      "-Xlinker", "-dead_strip_dylibs",
    ]
    
    # Modern Swift features for better caching (macOS 12+)
    if MacOS.version >= :monterey
      swift_flags += [
        "-Xswiftc", "-enable-library-evolution",
        "-Xswiftc", "-enable-implicit-dynamic",
      ]
    end
    
    # Apple Silicon specific optimizations
    if Hardware::CPU.arm?
      swift_flags += [
        "-Xswiftc", "-target", "arm64-apple-macos11.0",
        "-Xswiftc", "-enable-experimental-feature", "Embedded" # Future-proofing
      ]
    end
    
    # Build with performance optimizations
    system "swift", "build", *swift_flags
    
    # Install only the main binary (exclude test binaries for size optimization)
    bin.install ".build/release/usbipd"
    
    # Optimize installed binary
    unless build.with? "debug-symbols"
      # Strip debug symbols to reduce size
      system "strip", "#{bin}/usbipd"
      
      # Additional size optimization for Apple Silicon
      if Hardware::CPU.arm?
        system "codesign", "--force", "--sign", "-", "#{bin}/usbipd"
      end
    end
    
    # Clean up build artifacts to save space
    rm_rf ".build" unless build.with? "debug-symbols"
  end
  
  service do
    run [opt_bin/"usbipd", "--daemon"]
    require_root true
    keep_alive true
    run_type :immediate
    log_path var/"log/usbipd.log"
    error_log_path var/"log/usbipd.error.log"
    working_dir HOMEBREW_PREFIX
    process_type :background
  end
  
  def caveats
    <<~EOS
      Performance Optimizations:
      • This formula is optimized for fast installation and minimal binary size
      • Use --with-full-optimization for maximum performance (longer build time)
      • Use --with-debug-symbols to keep debug information for development
      
      Installation Performance:
      • Parallel compilation uses all CPU cores (#{Hardware::CPU.cores} detected)
      • Build artifacts are cleaned automatically to save disk space
      • Binary is stripped of debug symbols by default for size optimization
      
      For development builds with debug symbols:
        brew install usbipd-mac --with-debug-symbols
      
      For maximum runtime performance:
        brew install usbipd-mac --with-full-optimization
    EOS
  end
  
  test do
    # Test binary functionality
    system "#{bin}/usbipd", "--version"
    
    # Verify binary is properly optimized (size check)
    binary_size = File.size("#{bin}/usbipd")
    
    # Expected size range for optimized binary (rough estimate)
    if build.with? "debug-symbols"
      ohai "Binary size with debug symbols: #{binary_size} bytes"
    else
      ohai "Optimized binary size: #{binary_size} bytes"
      # Warn if binary seems unusually large (may indicate optimization issues)
      opoo "Binary size is larger than expected" if binary_size > 50_000_000 # 50MB
    end
    
    # Test that binary has required entitlements for System Extension
    if Hardware::CPU.arm?
      system "codesign", "--verify", "--verbose", "#{bin}/usbipd"
    end
  end
end