# Design QA

- Reference: `assets/design/reference-390x844.png`
- Implementation: `test/goldens/home_ready_rgb.png`
- Combined comparison: `design-qa-comparison-final.png`
- Viewport and state: 390 x 844, rear-camera ready state

## Review

- P0: none
- P1: none
- P2: none
- Layout: camera remains the dominant surface; rounded bottom control panel, status pill, supporting copy, one primary action, and recording link follow the selected direction
- Typography: bundled Noto Sans SC renders all Chinese UI text consistently
- Assets: real generated packing scene is used; visible controls use Flutter Material icons
- Interaction coverage: primary start/stop action, camera retry, recordings navigation, playback, and marker seeking are wired

Final result: passed
