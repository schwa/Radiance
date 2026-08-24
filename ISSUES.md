# ISSUES.md

---

## 1: Adopt MetalSprocketsGaussianSplats buffer pooling

+++
status: new
priority: medium
kind: enhancement
labels: performance, dependencies
created: 2026-03-31T20:00:13Z
+++

MetalSprocketsGaussianSplats now has buffer pooling for sort index buffers (issue #22).

Update Radiance to use the new release pattern:

```swift
.task {
    for await indices in sortManager.sortedIndicesStream {
        if let old = sortedIndices {
            sortManager.release(old)
        }
        sortedIndices = indices
    }
}
```

This reduces memory allocations during rendering by reusing index buffers instead of allocating new ones each frame.

---

## 2: Multi-cloud rendering performs CPU sorting

+++
status: new
priority: high
kind: task
labels: rendering, performance
created: 2026-08-24T23:09:54Z
+++

Multi-cloud rendering requests AsyncSortManager sorts whenever the camera or scene transform changes.

Expected: interactive multi-cloud rendering keeps splat sorting on the GPU.

Actual: every relevant view change schedules CPU sorting before rendering.

---

## 3: Single-cloud loading creates an unused CPU sort manager

+++
status: new
priority: medium
kind: task
labels: rendering, performance
created: 2026-08-24T23:09:54Z
+++

Loading a single cloud creates an AsyncSortManager even when the active renderer is Spark GPU.

Expected: the default GPU renderer does not allocate or maintain CPU sorting infrastructure.

Actual: SplatViewModel creates a CPU sort manager for loaded clouds regardless of the selected renderer.

---

## 4: Quick Look previews perform CPU sorting

+++
status: new
priority: high
kind: task
labels: rendering, quicklook, performance
created: 2026-08-24T23:09:54Z
+++

Quick Look splat previews depend on AsyncSortManager and request a CPU sort whenever the camera changes.

Expected: preview rendering sorts splats on the GPU.

Actual: preview interaction routes through the CPU-sorted Spark pipeline.

---

## 5: Immersive rendering performs CPU sorting

+++
status: new
priority: high
kind: task
labels: rendering, visionos, performance
created: 2026-08-24T23:09:54Z
+++

visionOS immersive rendering owns an AsyncSortManager and requests CPU sorts as the camera changes.

Expected: immersive rendering keeps per-frame splat sorting on the GPU.

Actual: head movement causes the immersive path to request CPU-sorted indices.

---

## 6: Offscreen rendering performs synchronous CPU sorting

+++
status: closed
priority: high
kind: task
labels: rendering, performance, foundation-models
created: 2026-08-24T23:09:54Z
updated: 2026-08-24T23:14:18Z
closed: 2026-08-24T23:14:18Z
+++

Screenshot export and Best View candidate generation use the shared offscreen renderer, which synchronously sorts splats on the CPU before every image. Best View repeats this for all six candidates.

Expected: offscreen rendering, screenshots, and model-analysis renders sort splats on the GPU.

Actual: each image blocks on sortNowSync before rendering.

- `2026-08-24T23:14:18Z`: The shared offscreen renderer now uses GPUSortedSplatRenderPipeline, covering screenshots and Best View candidate renders.

---

## 7: Automatic image classification triggers CPU sorting during normal rendering

+++
status: closed
priority: high
kind: bug
labels: rendering, performance, vision
created: 2026-08-24T23:10:29Z
updated: 2026-08-24T23:11:38Z
closed: 2026-08-24T23:11:38Z
+++

In normal single-cloud Spark GPU mode, camera and scene changes automatically start image classification. Preparing the classification image uses the synchronous CPU-sorted offscreen renderer.

Expected: selecting Spark GPU mode does not perform CPU sorting during ordinary interactive rendering or background analysis.

Actual: moving the camera triggers background classification, which calls the offscreen render path and blocks on sortNowSync.

- `2026-08-24T23:11:38Z`: Image classification now starts only while the Analysis inspector is selected; ordinary Spark GPU rendering no longer invokes the CPU-sorted offscreen path.
- `2026-08-24T23:14:18Z`: Corrected implementation: automatic classification remains enabled. The shared offscreen renderer now uses Spark GPU sorting instead of hiding classification outside the Analysis inspector.

---
