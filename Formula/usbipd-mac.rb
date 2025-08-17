class UsbipdMac < Formula
  desc "macOS USB/IP protocol implementation for sharing USB devices over IP"
  homepage "https://github.com/beriberikix/usbipd-mac"
  url "https://github.com/beriberikix/usbipd-mac/archive/VERSION_PLACEHOLDER.tar.gz"
  version "VERSION_PLACEHOLDER"
  sha256 "SHA256_PLACEHOLDER"
  license "MIT"
  
  depends_on :macos => :big_sur
  depends_on :xcode => ["13.0", :build]
  
  def install
    # Simple, reliable build configuration
    system "swift", "build", "--configuration", "release", "--disable-sandbox"
    
    # Install the main binary
    bin.install ".build/release/usbipd"
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
      usbipd-mac requires System Extension approval and administrator privileges.
      
      After installation:
      1. Run 'sudo usbipd --install-extension' to install the System Extension
      2. Approve the System Extension in System Preferences > Security & Privacy
      3. A restart may be required for the System Extension to become active
      
      To start the service:
        sudo brew services start usbipd-mac
      
      To check status:
        usbipd status
    EOS
  end
  
  test do
    # Test that the binary runs and shows version
    system "#{bin}/usbipd", "--version"
  end
end