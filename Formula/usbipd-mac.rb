class UsbipDMac < Formula
  desc "macOS USB/IP protocol implementation for sharing USB devices over IP"
  homepage "https://github.com/beriberikix/usbipd-mac"
  url "https://github.com/beriberikix/usbipd-mac/archive/VERSION_PLACEHOLDER.tar.gz"
  version "VERSION_PLACEHOLDER"
  sha256 "SHA256_PLACEHOLDER"
  license "MIT"
  
  depends_on :macos => :big_sur
  depends_on :xcode => ["13.0", :build]
  
  def install
    system "swift", "build", "--configuration", "release", "--disable-sandbox"
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
  
  test do
    system "#{bin}/usbipd", "--version"
  end
end