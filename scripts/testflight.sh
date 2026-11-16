#!/bin/sh
# Archives Pourfect for iOS and uploads it to App Store Connect for TestFlight.
#
#   scripts/testflight.sh BUILD_NUMBER                 archive, then export + upload
#   scripts/testflight.sh BUILD_NUMBER --archive-only  archive only (no signing, nothing leaves the Mac)
#
# BUILD_NUMBER becomes CFBundleVersion (CURRENT_PROJECT_VERSION) and must be higher than every build
# already uploaded for this version. The version itself (MARKETING_VERSION) comes from the project.
# The archive is built unsigned; the export step signs it with the team's App Store distribution
# certificate (automatic signing, -allowProvisioningUpdates) and uploads it with the Apple ID
# signed in to Xcode (Settings > Accounts). Export options: scripts/ExportOptions.plist.
# Everything is written to a new temporary directory, printed at the start and the end.
set -eu

usage() {
    echo "usage: $0 BUILD_NUMBER [--archive-only]" >&2
    exit 64
}

[ $# -ge 1 ] && [ $# -le 2 ] || usage
build=$1
case $build in
    '' | .* | *. | *..* | *[!0-9.]*)
        echo "BUILD_NUMBER must be digits and dots, e.g. 7 or 1.0.7 (got '$build')" >&2
        exit 64
        ;;
esac
upload=yes
if [ $# -eq 2 ]; then
    [ "$2" = "--archive-only" ] || usage
    upload=no
fi

root=$(cd "$(dirname "$0")/.." && pwd)
tmp=${TMPDIR:-/tmp}
out=$(mktemp -d "${tmp%/}/pourfect-release.XXXXXX")
archive="$out/Pourfect.xcarchive"
echo "Output: $out"

xcodebuild \
    -project "$root/Pourfect.xcodeproj" \
    -scheme Pourfect \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$out/DerivedData" \
    -archivePath "$archive" \
    archive \
    CODE_SIGNING_ALLOWED=NO \
    CURRENT_PROJECT_VERSION="$build"

info="$archive/Products/Applications/Pourfect.app/Info.plist"
bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")
built=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")
if [ "$bundle_id" != "dev.qbi.pourfect" ] || [ "$built" != "$build" ]; then
    echo "Unexpected archive: bundle id $bundle_id, build $built (wanted dev.qbi.pourfect, $build)" >&2
    exit 1
fi
echo "Archived $bundle_id $version ($built)"

if [ "$upload" = no ]; then
    echo "Archive only: $archive"
    exit 0
fi

xcodebuild \
    -exportArchive \
    -archivePath "$archive" \
    -exportOptionsPlist "$root/scripts/ExportOptions.plist" \
    -exportPath "$out/export" \
    -allowProvisioningUpdates

echo "Uploaded $version ($built) to App Store Connect. Output: $out"
