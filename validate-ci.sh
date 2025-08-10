#!/bin/bash

# Validate CI locally - runs the exact same commands as CI
set -e

echo "🔍 Validating project for CI compatibility..."
echo ""

# Step 1: SwiftLint validation
echo "📋 Running SwiftLint validation (strict mode)..."
if swiftlint lint --strict --reporter xcode; then
    echo "✅ SwiftLint validation: PASSED"
else
    echo "❌ SwiftLint validation: FAILED"
    exit 1
fi
echo ""

# Step 2: Dependency resolution  
echo "📦 Resolving dependencies..."
if swift package resolve; then
    echo "✅ Dependency resolution: PASSED"
else
    echo "❌ Dependency resolution: FAILED"  
    exit 1
fi
echo ""

# Step 3: Build validation
echo "🔨 Building project..."
if swift build --verbose; then
    echo "✅ Build validation: PASSED"
else
    echo "❌ Build validation: FAILED"
    exit 1
fi
echo ""

echo "🎉 All CI validations PASSED! Ready for GitHub Actions."