# Screenshot image generation

## Squat camera preview

- Asset: `src/squat.png`
- Tool: built-in `image_gen` (no CLI/API fallback).
- Reference: `src/pushup.png`, the existing generated photograph used by frame 02.
- Use: photorealistic person in frame 04's camera inset; HTML supplies the localized counter and guidance. This is generated marketing imagery, not a live camera capture.

Final prompt:

```text
Use case: photorealistic-natural.
Asset type: realistic camera preview photograph for a squat-rep counter in an iPhone app marketing screenshot.
Input image: style and subject reference only. Match the existing push-up image's adult man, charcoal workout shirt, black shorts, bright home living room, wood floor, warm daylight and natural photographic texture.
Primary request: create a new photograph of this adult man doing a bodyweight squat, at the bottom of the squat, viewed from a slightly front three-quarter angle so the bent knees and hips are clearly visible. Both feet flat on the floor, knees tracking over toes, torso controlled and upright, arms extended forward for balance. Anatomically realistic hands and legs.
Composition: landscape 4:3 image; entire person from head to shoes clearly visible, centered, occupying most of the frame height with a small margin above and below. The camera is propped at about knee height, like a real phone exercise recording. Face, torso, thighs and shoes all sharp.
Constraints: photorealistic human, not a drawing, mannequin, avatar, CGI or illustration. No text, UI, numbers, borders, skeleton tracking dots, watermark or logos. No extra people. Natural modest workout clothing.
```
