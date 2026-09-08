# Yeoback brand film

[Watch the film](../images/yeoback-film.mp4) · [Editable cover](hero.html) · [Native app design in Figma](https://www.figma.com/design/olCrS1PxKWJjMiVlGbC3zR?node-id=196-416)

The ivory frame holds two coral blocks and an open bay. That space is the central idea of **여백**: room around what matters. The slow camera movement preserves the shape; the typography stays still and readable.

## Production

- **Artwork:** GPT Image, guided by Yeoback’s existing icon. The studio image is conceptual brand art, not an app screenshot.
- **Motion:** Higgsfield, Seedance 2.0 image-to-video, generated from the studio image on September 8, 2026. One continuous six-second shot.
- **Typography:** deterministic AppKit composition using the macOS system font. Text is added after generation so it cannot drift or change spelling.
- **Delivery:** 1920 × 1080, H.264, 24 fps, 6.04 seconds, silent. The film does not demonstrate cleanup or claim recovered capacity.
- **App evidence:** README screenshots show the actual native app with disposable sample files. The film is presented separately from those screenshots.

`hero.html` contains the desktop and portrait cover layout. `render-titles.swift` produces the transparent 1080p title layer:

```sh
swift docs/github/marketing/render-titles.swift /tmp/yeoback-titles.png
```

The final MP4 is checked in. Its frames were inspected for stable icon geometry, readable text, overlap, and cropping; browser playback was also checked. This is a short brand film, not a walkthrough of every feature.
