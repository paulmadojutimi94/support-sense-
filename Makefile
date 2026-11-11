.PHONY: test eval app open clean

## swift test — unit, parity, quality-gate and latency tests (macOS or Linux)
test:
	swift test

## Re-run the evaluation; rewrites eval/results.json, eval/RESULTS.md, eval/golden.json
eval:
	python3 tools/eval.py

## Generate the Xcode project (requires: brew install xcodegen)
app:
	cd App && xcodegen generate

open: app
	open App/SupportSense.xcodeproj

clean:
	rm -rf .build App/SupportSense.xcodeproj
