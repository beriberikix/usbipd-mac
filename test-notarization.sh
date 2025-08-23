#!/bin/bash
# Test notarization credentials

echo "🔍 Testing notarization credentials..."

# Check if required environment variables would be available
if [ -z "$NOTARIZATION_USERNAME" ]; then
    echo "❌ NOTARIZATION_USERNAME not set"
    echo "   Set with: export NOTARIZATION_USERNAME='your-apple-id@example.com'"
    exit 1
fi

if [ -z "$NOTARIZATION_PASSWORD" ]; then
    echo "❌ NOTARIZATION_PASSWORD not set" 
    echo "   Set with: export NOTARIZATION_PASSWORD='your-app-specific-password'"
    exit 1
fi

echo "✅ Environment variables configured"
echo "   Username: $NOTARIZATION_USERNAME"
echo "   Password: [REDACTED]"

# Test notarytool authentication
echo "🔍 Testing notarytool authentication..."
if xcrun notarytool history --apple-id "$NOTARIZATION_USERNAME" --password "$NOTARIZATION_PASSWORD" --team-id "592A3U6J26" > /dev/null 2>&1; then
    echo "✅ Notarization credentials are valid"
    echo "✅ Team ID 592A3U6J26 is accessible"
else
    echo "❌ Notarization authentication failed"
    echo "   Possible issues:"
    echo "   • Incorrect Apple ID"
    echo "   • Invalid app-specific password"
    echo "   • Team ID mismatch"
    echo "   • Apple ID not enrolled in Apple Developer Program"
    exit 1
fi

echo "🎉 Notarization test completed successfully!"