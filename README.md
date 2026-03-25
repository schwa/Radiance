# Radiance

A Gaussian splat viewer for macOS, iOS, and visionOS, built on [MetalSprocketsGaussianSplats](https://github.com/schwa/MetalSprocketsGaussianSplats).

## Features

- Single and multi-cloud splat rendering
- Debug visualization modes (distance, size, depth, opacity, normal, aspect ratio, cloud index)
- Bounding box culling
- Spherical harmonics support
- Camera controls (turntable, room, spatial scene)
- Screenshot export
- QuickLook preview extension for splat files
- visionOS immersive mode
- FPS and sort performance monitoring

## Requirements

- macOS 26 / iOS 26 / visionOS 26
- Apple Silicon

## Getting Started

Open `Radiance.xcodeproj` in Xcode and build.

The app loads `.splat`, `.ply`, `.spz`, and `.sog` files. Sample splats are included in the `Sample Splats` directory.
