# ISSUES.md

---

## 1: Adopt MetalSprocketsGaussianSplats buffer pooling

+++
status: closed
priority: medium
kind: enhancement
labels: performance, dependencies
created: 2026-03-31T20:00:13Z
updated: 2026-08-24T23:24:12Z
closed: 2026-08-24T23:24:12Z
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

- `2026-08-24T23:24:12Z`: Won't fix.

---

## 2: Multi-cloud rendering performs CPU sorting

+++
status: open
priority: high
kind: task
labels: rendering, performance, effort:l
created: 2026-08-24T23:09:54Z
updated: 2026-08-25T02:18:27Z
+++

Multi-cloud rendering requests AsyncSortManager sorts whenever the camera or scene transform changes.

Expected: interactive multi-cloud rendering keeps splat sorting on the GPU.

Actual: every relevant view change schedules CPU sorting before rendering.

- `2026-08-25T02:26:36Z`: Inspected MetalSprocketsGaussianSplats GPU sorting APIs and the current multi-cloud render pass. Punting: GPUSortedSplatRenderPipeline accepts one GPUSplatCloud, while correct alpha compositing requires one global ordering across clouds; independently sorting each cloud would render incorrectly. Unblocker: add/identify a GPU sort API for multiple clouds or a supported way to combine their GPU buffers before sorting.

---

## 3: Single-cloud loading creates an unused CPU sort manager

+++
status: closed
priority: medium
kind: task
labels: rendering, performance
created: 2026-08-24T23:09:54Z
updated: 2026-08-24T23:23:53Z
closed: 2026-08-24T23:23:53Z
+++

Loading a single cloud creates an AsyncSortManager even when the active renderer is Spark GPU.

Expected: the default GPU renderer does not allocate or maintain CPU sorting infrastructure.

Actual: SplatViewModel creates a CPU sort manager for loaded clouds regardless of the selected renderer.

- `2026-08-24T23:23:53Z`: Single-cloud Spark GPU rendering no longer creates or requires the view model's CPU sort manager.

---

## 4: Quick Look previews perform CPU sorting

+++
status: closed
priority: high
kind: task
labels: rendering, quicklook, performance
created: 2026-08-24T23:09:54Z
updated: 2026-08-24T23:23:53Z
closed: 2026-08-24T23:23:53Z
+++

Quick Look splat previews depend on AsyncSortManager and request a CPU sort whenever the camera changes.

Expected: preview rendering sorts splats on the GPU.

Actual: preview interaction routes through the CPU-sorted Spark pipeline.

- `2026-08-24T23:23:53Z`: Quick Look previews now use GPUSortedSplatRenderPipeline and GPUSortResources.

---

## 5: Immersive rendering performs CPU sorting

+++
status: closed
priority: high
kind: task
labels: rendering, visionos, performance
created: 2026-08-24T23:09:54Z
updated: 2026-08-24T23:23:53Z
closed: 2026-08-24T23:23:53Z
+++

visionOS immersive rendering owns an AsyncSortManager and requests CPU sorts as the camera changes.

Expected: immersive rendering keeps per-frame splat sorting on the GPU.

Actual: head movement causes the immersive path to request CPU-sorted indices.

- `2026-08-24T23:23:53Z`: visionOS immersive rendering now encodes SplatImmersiveGPUSortElement before the render pass and renders with Spark GPU.

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

## 8: Document view has an excessively broad invalidation boundary

+++
status: open
priority: high
kind: task
labels: swiftui, architecture, performance, effort:xl
created: 2026-08-25T02:10:46Z
updated: 2026-08-25T02:18:27Z
+++

SplatDocumentContentView owns rendering, Vision analysis, Best View search, image generation, camera math, file coordination, and most screen composition. Changes to frequently updated state can reevaluate unrelated UI and the mixed responsibilities make behavior difficult to isolate and test.

- `2026-08-25T02:18:13Z`: Related to #9: both reduce broad SwiftUI invalidation boundaries; #8 covers the document view and #9 the render view.

---

## 9: Render view sections share one invalidation boundary

+++
status: open
priority: medium
kind: task
labels: swiftui, performance, effort:l
created: 2026-08-25T02:10:46Z
updated: 2026-08-25T02:18:27Z
+++

SplatRenderView organizes substantial camera, rendering, overlay, and inspector regions as computed view properties. These regions remain part of the parent view's invalidation boundary despite their visual separation.

- `2026-08-25T02:18:13Z`: Related to #8: both reduce broad SwiftUI invalidation boundaries; #9 is scoped to SplatRenderView.

---

## 10: Best View attempt ribbon shares sheet invalidation

+++
status: open
priority: medium
kind: task
labels: swiftui, performance, best-view, effort:s
created: 2026-08-25T02:10:46Z
updated: 2026-08-25T02:18:27Z
+++

The Best View attempt ribbon contains collection rendering, scroll coordination, animation, rejection overlays, and context menus inside BestViewSheet's invalidation boundary. Updates elsewhere in the sheet reevaluate this independent region.

---

## 11: Recent documents list copies its collection during rendering

+++
status: open
priority: low
kind: task
labels: swiftui, performance, effort:xs
created: 2026-08-25T02:10:46Z
updated: 2026-08-25T02:18:27Z
+++

SplashScene wraps recentDocumentURLs.enumerated() in Array inside the List body. Every body evaluation allocates and copies the collection even though the enumerated collection is directly usable by ForEach.

---

## 12: Bounds slider rows use manual label-value layout

+++
status: open
priority: low
kind: task
labels: swiftui, accessibility, effort:xs
created: 2026-08-25T02:10:46Z
updated: 2026-08-25T02:18:27Z
+++

NormalizedBoundsSlider and AbsoluteBoundsSlider manually align labels and values with HStack and Spacer. This bypasses the standard form alignment, truncation, and Dynamic Type behavior provided by SwiftUI's semantic label-value container.

---

## 13: Legacy tile debug view uses a soft-deprecated corner modifier

+++
status: open
priority: low
kind: task
labels: swiftui, legacy, effort:xs
created: 2026-08-25T02:10:46Z
updated: 2026-08-25T02:18:27Z
+++

TileDebugViews uses the legacy cornerRadius modifier rather than the current shape clipping API preferred by the project's SwiftUI conventions.

---

## 14: App target is not checked under Swift 6 strict concurrency

+++
status: open
priority: high
kind: task
labels: swift, concurrency, build-settings, effort:l
created: 2026-08-25T02:12:55Z
updated: 2026-08-25T02:18:27Z
+++

The shared Xcode configuration enables approachable concurrency and MainActor default isolation but sets SWIFT_VERSION to 5.0 and leaves complete strict-concurrency checking disabled. Data-race diagnostics that the project intends to satisfy under Swift 6.2 are therefore not enforced consistently with the RadianceSupport package, which already uses Swift 6.

- `2026-08-25T02:27:44Z`: Attempted Swift 6 plus complete strict-concurrency checking. Build failed in existing code: Shape conformance isolation, timer and Notification sending races, SplatScene initialization, URLSession delegate Sendable closures, and AsyncView metatype capture. Reverted the setting change; the issue remains open for an incremental migration.

---

## 15: Security-scoped resource tracking has unsynchronized mutable state

+++
status: closed
priority: high
kind: bug
labels: swift, concurrency, resources, effort:s
created: 2026-08-25T02:12:55Z
updated: 2026-08-25T02:21:18Z
closed: 2026-08-25T02:21:18Z
+++

ScopedResourceAccess marks its mutable accessingURLs collection nonisolated(unsafe). startAccessing mutates the collection from the type's isolation context while nonisolated stopAccessing and deinit read and clear it without synchronization. Concurrent teardown or reload can race, potentially leaking access grants or stopping a resource while it is in use.

- `2026-08-25T02:21:18Z`: Regression test exempt: security-scoped URL access and concurrent deinitialization are macOS lifecycle behavior without an existing injectable unit boundary. Verified with a macOS build.
- `2026-08-25T02:21:18Z`: Protected resource URL ownership with Synchronization.Mutex and atomically drained tracked URLs.

---

## 16: An older document load can overwrite a newer selection

+++
status: closed
priority: high
kind: bug
labels: swift, concurrency, documents, effort:m
created: 2026-08-25T02:12:55Z
updated: 2026-08-25T02:22:41Z
closed: 2026-08-25T02:22:41Z
+++

Single-document loading starts an unstructured task whenever fileURL changes. A load suspends while computing bounds and no task handle or generation check distinguishes it from a later load. If the user changes documents quickly, an older operation can resume last and replace the newer cloud, bounds, and loading state.

- `2026-08-25T02:22:41Z`: Regression test exempt: reproducing rapid FileDocument identity changes requires SwiftUI document lifecycle integration that the current unit target does not expose. Verified cancellation guards and macOS build.
- `2026-08-25T02:22:41Z`: Made document loading lifecycle-bound with task(id:) and prevented cancelled loads from publishing bounds, clouds, or errors.

---

## 17: Detached rendering work ignores analysis cancellation

+++
status: closed
priority: medium
kind: bug
labels: swift, concurrency, analysis, cancellation, effort:m
created: 2026-08-25T02:12:55Z
updated: 2026-08-25T02:33:29Z
closed: 2026-08-25T02:33:29Z
+++

Classification, Best View, and image-description operations wrap offscreen rendering in Task.detached and then await the detached task. Detached tasks do not inherit cancellation from the stored analysis tasks, so cancelling or replacing analysis cannot stop the render and completion is delayed until that independent work finishes.

- `2026-08-25T02:18:13Z`: Related to #20: both cover cancellation and stale work in Analysis; #17 concerns detached rendering and #20 image-description task ownership.
- `2026-08-25T02:18:13Z`: Also related to #18, which tracks the same detached-task cancellation failure in AsyncView.
- `2026-08-25T02:33:29Z`: Regression test exempt: offscreen Metal rendering and cancellation require a live GPU/render lifecycle not exposed by the current unit target. Verified structured cancellation checks and macOS build.
- `2026-08-25T02:33:29Z`: Replaced detached renders with an explicitly concurrent structured helper that checks cancellation before and after rendering.

---

## 18: AsyncView work survives SwiftUI task cancellation

+++
status: closed
priority: medium
kind: bug
labels: swift, concurrency, cancellation, effort:xs
created: 2026-08-25T02:12:55Z
updated: 2026-08-25T02:28:32Z
closed: 2026-08-25T02:28:32Z
+++

AsyncView launches its action in Task.detached from a SwiftUI .task modifier. When the view disappears, SwiftUI cancels the parent task but the detached action continues independently and can retain resources or perform obsolete work.

- `2026-08-25T02:18:13Z`: Related to #17: both involve detached work escaping parent cancellation, but #18 is the reusable AsyncView helper.
- `2026-08-25T02:28:32Z`: Regression test exempt: AsyncView is a SwiftUI lifecycle wrapper and the current test target has no view-hosting cancellation harness; the fix is the direct structured await in its .task. Verified with a macOS build.
- `2026-08-25T02:28:32Z`: Kept the action in SwiftUI's lifecycle task and ignored normal cancellation instead of detaching it.

---

## 19: Download operations are not connected to Swift task cancellation

+++
status: closed
priority: high
kind: bug
labels: swift, concurrency, downloads, cancellation, effort:m
created: 2026-08-25T02:12:55Z
updated: 2026-08-25T02:26:08Z
closed: 2026-08-25T02:26:08Z
+++

ModelDownloadView and SampleAssetsDownloadView bridge URLSession download tasks with checked continuations but do not connect cancellation of the awaiting Swift task to URLSessionDownloadTask.cancel(). Button actions also launch untracked tasks. Removing the view or cancelling its Swift task can leave downloads running and continuations waiting until URLSession completes independently.

- `2026-08-25T02:26:08Z`: Regression test exempt: the current tests do not expose the URLSession delegate/download lifecycle or SwiftUI view disappearance. Verified task ownership, cancellation teardown, and macOS build.
- `2026-08-25T02:26:08Z`: Tracked download operations, cancelled Swift and URLSession tasks together, and cancelled downloads when their views disappear.

---

## 20: Image description work is untracked and reports cancellation as failure

+++
status: closed
priority: medium
kind: bug
labels: swift, concurrency, analysis, cancellation, effort:s
created: 2026-08-25T02:12:55Z
updated: 2026-08-25T02:30:06Z
closed: 2026-08-25T02:30:06Z
+++

Image description starts an unstructured task without retaining its handle. The operation cannot be cancelled when the document or view changes, and its catch path treats cancellation like an analysis failure. A stale description can finish after the rendered view has changed and replace current analysis fields.

- `2026-08-25T02:18:13Z`: Related to #17: both cover cancellation and stale work in Analysis; #20 is scoped to image-description task ownership.
- `2026-08-25T02:30:06Z`: Regression test exempt: the stale publication requires Foundation Models plus a rendered SwiftUI document lifecycle, which the current unit target cannot host. Verified cancellation checks and macOS build.
- `2026-08-25T02:30:06Z`: Tracked and cancelled image-description work on replacement/document changes, suppressed cancellation errors, and checked cancellation before publishing results.

---
