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
    public static let current = "0.5.2"
}
