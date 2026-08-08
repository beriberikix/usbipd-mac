// Version.swift
// The single place the shipped version number is written down.

import Foundation

/// The version this binary reports.
///
/// This lived as the literal "0.1.0" in three separate print statements, so every
/// release since the beginning shipped a binary reporting 0.1.0 no matter which tag it
/// was built from. Keeping it in one place is what makes `usbipd --version` mean
/// something.
public enum USBIPDVersion {
    public static let current = "0.5.3"

    /// Whether this binary was built with optimisations.
    ///
    /// `usbipd -v` printed the literal "Build: Development" from main.swift, so a
    /// Homebrew-installed release binary claimed to be a development build. A correct
    /// implementation already existed in CommandLineParser, but main.swift intercepts
    /// -v before the parser is reached, so the wrong one always won.
    public static var build: String {
        #if DEBUG
        return "debug"
        #else
        return "release"
        #endif
    }
}
