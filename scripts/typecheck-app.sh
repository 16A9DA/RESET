#!/bin/sh
# Approximate type check of the iOS app target on a machine WITHOUT Xcode.
# It uses the macOS SDK's Mac Catalyst (UIKit) frameworks, and swaps SwiftData for a small stub because
# Xcode's SwiftData macro plugin is not available. It catches most type errors but is NOT a real build:
# SwiftData macro behavior, entitlements, signing and runtime are unchecked. Use Xcode for the real build.
set -e
cd "$(dirname "$0")/.."
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk
[ -d "$SDK" ] || SDK=$(xcrun --show-sdk-path)
WORK=${TMPDIR:-/tmp}/reset-typecheck
rm -rf "$WORK" && mkdir -p "$WORK/out" "$WORK/src"
FW="-F $SDK/System/iOSSupport/System/Library/Frameworks"
TARGET="-target arm64-apple-ios17.0-macabi -sdk $SDK -swift-version 5"

swiftc $TARGET $FW -parse-as-library -emit-module -module-name ResetCore -emit-module-path "$WORK/out/ResetCore.swiftmodule" \
  -emit-library -static -o "$WORK/out/libResetCore.a" ResetCore/Sources/ResetCore/*.swift
swiftc $TARGET $FW -parse-as-library -emit-module -module-name SDStub -emit-module-path "$WORK/out/SDStub.swiftmodule" \
  -emit-library -static -o "$WORK/out/libSDStub.a" scripts/typecheck/SDStub.swift

cp -R RESET "$WORK/src/RESET"
cp -R Shared "$WORK/src/Shared"
python3 - "$WORK/src/RESET" <<'PY'
import re, sys, pathlib
for f in pathlib.Path(sys.argv[1]).rglob("*.swift"):
    s = f.read_text()
    s = s.replace("import SwiftData", "import SDStub")
    s = re.sub(r"@Model\s*\n(\s*)final class (\w+) \{", r"@Observable\n\1final class \2: PersistentModel {", s)
    s = s.replace("@Attribute(.unique) ", "")
    s = s.replace("#Predicate", "makePredicate")
    if "@Observable" in s and "import Observation" not in s:
        s = "import Observation\n" + s
    f.write_text(s)
PY
# DataScannerViewController does not exist on Mac Catalyst, only on iOS. Replace that one file with a same-API stub.
cat > "$WORK/src/RESET/Features/Nutrition/BarcodeScanner.swift" <<'SW'
import SwiftUI
struct BarcodeScanner: View {
    var onCode: (String) -> Void
    static var supported: Bool { true }
    var body: some View { EmptyView() }
}
SW
cat > "$WORK/src/Conformances.swift" <<'SW'
import SDStub
// Real SwiftData makes every model Identifiable.
extension Place: Identifiable {}
extension TrackedSession: Identifiable {}
extension MealRecord: Identifiable {}
extension SavedMeal: Identifiable {}
extension WaterRecord: Identifiable {}
extension CaffeineRecord: Identifiable {}
extension SavedDrink: Identifiable {}
extension SleepRecord: Identifiable {}
extension ActivityRecord: Identifiable {}
extension WorkoutRecord: Identifiable {}
extension WorkoutPlan: Identifiable {}
extension CheckIn: Identifiable {}
extension ChatMessage: Identifiable {}
extension WeightRecord: Identifiable {}
extension LocationEvent: Identifiable {}
extension UserProfile: Identifiable {}
extension PurchaseDraft: Identifiable {}
extension PurchaseRuleRecord: Identifiable {}
SW
if [ -n "$PROBE" ]; then
  echo 'let probeError: Int = "not an int"' >> "$WORK/src/RESET/Features/Shared/Theme.swift"
  echo 'func probe2(p: UserProfile) { p.noSuchProperty = 3 }' >> "$WORK/src/RESET/Features/Shared/Theme.swift"
fi
swiftc -typecheck $TARGET $FW -I "$WORK/out" $(find "$WORK/src" -name '*.swift') 2>&1 | sed "s#$WORK/src/##" | grep -E "error:" | grep -v "^ " || echo "typecheck: no errors"

# The widget extension: its own sources plus the shared folder, no SwiftData or ResetCore.
swiftc -typecheck $TARGET $FW $(find Shared RESETWidgets -name '*.swift') 2>&1 | grep -E "error:" | grep -v "^ " || echo "widget typecheck: no errors"
