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
status: closed
priority: high
kind: task
labels: rendering, performance, effort:l, area:rendering, area:performance
created: 2026-08-24T23:09:54Z
updated: 2026-09-10T02:27:28Z
closed: 2026-09-10T02:27:28Z
+++

Multi-cloud rendering requests AsyncSortManager sorts whenever the camera or scene transform changes.

Expected: interactive multi-cloud rendering keeps splat sorting on the GPU.

Actual: every relevant view change schedules CPU sorting before rendering.

- `2026-08-25T02:26:36Z`: Inspected MetalSprocketsGaussianSplats GPU sorting APIs and the current multi-cloud render pass. Punting: GPUSortedSplatRenderPipeline accepts one GPUSplatCloud, while correct alpha compositing requires one global ordering across clouds; independently sorting each cloud would render incorrectly. Unblocker: add/identify a GPU sort API for multiple clouds or a supported way to combine their GPU buffers before sorting.
- `2026-08-27T06:16:46Z`: Rechecked the resolved MetalSprocketsGaussianSplats API. GPUSortedSplatRenderPipeline still accepts a single GPUSplatCloud, while this view needs one globally sorted index stream across multiple clouds for correct alpha compositing. Concrete unblocker remains a dependency API that GPU-sorts multiple clouds as one logical stream (or exposes a combined GPU cloud/buffer view).
- `2026-09-09T23:50:47Z`: Re-checked MetalSprocketsGaussianSplats: GPUSplatSortComputePass/GPUSortedSplatRenderPipeline are still single-cloud (one cloud + one modelMatrix per sort slot); only CPU paths (SplatSorter/AsyncSortManager) accept [GPUSplatCloud]. Punting: still blocked on a dependency API that GPU-sorts multiple clouds as one globally ordered stream. Unblocker: add multi-cloud support to the GPU sort in MetalSprocketsGaussianSplats first.

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
labels: swiftui, architecture, performance, effort:xl, area:swiftui, area:architecture, area:performance
created: 2026-08-25T02:10:46Z
updated: 2026-09-09T23:04:06Z
+++

SplatDocumentContentView owns rendering, Vision analysis, Best View search, image generation, camera math, file coordination, and most screen composition. Changes to frequently updated state can reevaluate unrelated UI and the mixed responsibilities make behavior difficult to isolate and test.

- `2026-08-25T02:18:13Z`: Related to #9: both reduce broad SwiftUI invalidation boundaries; #8 covers the document view and #9 the render view.

---

## 9: Render view sections share one invalidation boundary

+++
status: closed
priority: medium
kind: task
labels: swiftui, performance, effort:l
created: 2026-08-25T02:10:46Z
updated: 2026-08-27T06:16:35Z
closed: 2026-08-27T06:16:35Z
+++

SplatRenderView organizes substantial camera, rendering, overlay, and inspector regions as computed view properties. These regions remain part of the parent view's invalidation boundary despite their visual separation.

- `2026-08-25T02:18:13Z`: Related to #8: both reduce broad SwiftUI invalidation boundaries; #9 is scoped to SplatRenderView.
- `2026-08-27T06:16:35Z`: Split rendering and bounding-box overlay regions into dedicated SwiftUI view invalidation boundaries. No regression test added because this is a structural performance refactor; validated by building the app and running the available package test suite.

---

## 10: Best View attempt ribbon shares sheet invalidation

+++
status: closed
priority: medium
kind: task
labels: swiftui, performance, best-view, effort:s
created: 2026-08-25T02:10:46Z
updated: 2026-08-25T02:35:33Z
closed: 2026-08-25T02:35:33Z
+++

The Best View attempt ribbon contains collection rendering, scroll coordination, animation, rejection overlays, and context menus inside BestViewSheet's invalidation boundary. Updates elsewhere in the sheet reevaluate this independent region.

- `2026-08-25T02:35:33Z`: Regression test exempt: this is a pure SwiftUI view-boundary refactor with no behavior change. Verified with a macOS build and retained a dedicated preview.
- `2026-08-25T02:35:33Z`: Extracted the attempt ribbon into a narrowly scoped view with its own invalidation boundary.

---

## 11: Recent documents list copies its collection during rendering

+++
status: open
priority: low
kind: task
labels: swiftui, performance, effort:xs, area:swiftui, area:performance
created: 2026-08-25T02:10:46Z
updated: 2026-09-09T23:04:06Z
+++

SplashScene wraps recentDocumentURLs.enumerated() in Array inside the List body. Every body evaluation allocates and copies the collection even though the enumerated collection is directly usable by ForEach.

---

## 12: Bounds slider rows use manual label-value layout

+++
status: open
priority: low
kind: task
labels: swiftui, accessibility, effort:xs, area:swiftui, area:accessibility
created: 2026-08-25T02:10:46Z
updated: 2026-09-09T23:04:06Z
+++

NormalizedBoundsSlider and AbsoluteBoundsSlider manually align labels and values with HStack and Spacer. This bypasses the standard form alignment, truncation, and Dynamic Type behavior provided by SwiftUI's semantic label-value container.

---

## 13: Legacy tile debug view uses a soft-deprecated corner modifier

+++
status: open
priority: low
kind: task
labels: swiftui, legacy, effort:xs, area:swiftui, area:legacy
created: 2026-08-25T02:10:46Z
updated: 2026-09-09T23:04:06Z
+++

TileDebugViews uses the legacy cornerRadius modifier rather than the current shape clipping API preferred by the project's SwiftUI conventions.

---

## 14: App target is not checked under Swift 6 strict concurrency

+++
status: closed
priority: high
kind: task
labels: swift, concurrency, build-settings, effort:l
created: 2026-08-25T02:12:55Z
updated: 2026-08-27T06:16:00Z
closed: 2026-08-27T06:16:00Z
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

## 21: Debug checkbox no longer works

+++
status: closed
priority: medium
kind: bug
labels: effort:s
created: 2026-08-27T03:27:34Z
updated: 2026-08-27T05:46:51Z
closed: 2026-08-27T05:46:51Z
+++

The debug checkbox is broken again.

Expected: Toggling the checkbox enables or disables the debug display.

Actual: The checkbox does not change the debug state.

- `2026-08-27T05:44:59Z`: Related to #29: both are regressions in debug/visualization controls.
- `2026-08-27T05:46:51Z`: Fixed by creating the single-document sort manager and routing debug rendering through it. macOS build passes.
- `2026-08-27T06:03:36Z`: Correction: debug mode now uses GPUSortedSplatDebugRenderPipeline with GPUSortResources. It does not create or depend on AsyncSortManager.

---

## 22: Add Interaction3D rotation cube

+++
status: closed
priority: medium
kind: feature
labels: effort:s
created: 2026-08-27T03:36:07Z
updated: 2026-09-10T00:05:02Z
closed: 2026-09-10T00:05:02Z
+++

Add the rotation cube provided by Interaction3D to the 3D viewer so users can inspect and change the current view orientation.

---

## 23: Add downloads window

+++
status: open
priority: medium
kind: feature
labels: effort:l
created: 2026-08-27T03:36:55Z
updated: 2026-08-27T05:44:48Z
+++

Add a compact Safari-style downloads window that opens near the top-right corner of the screen.

The window lists all downloads and their current status. All downloads in the app use this shared downloads UI. It is also accessible from a matching Downloads item in the Window menu.

- `2026-09-10T00:06:47Z`: Assessed in the autonomous run: implementation requires consolidating the two existing independent download flows (SampleAssetsDownloadView's URLSession delegate, ModelDownloadView/Sharp model) behind a shared observable download manager, then designing the window UX (floating panel vs regular window, per-item progress/cancel/retry, clear-completed, persistence across launches). effort:l with real design surface — punting per this run's obvious-solutions-only constraint. Unblocker: sketch the desired UX (or approve a minimal version: shared DownloadManager + plain Window scene listing progress rows with cancel, Window menu item) and it can be built in a dedicated session.

---

## 24: Add a reference grid to the 3D viewer

+++
status: closed
priority: medium
kind: enhancement
labels: effort:s
created: 2026-08-27T03:38:12Z
updated: 2026-08-27T06:26:35Z
closed: 2026-08-27T06:26:35Z
+++

Add an optional reference grid to the 3D viewer. MetalSprocketsAddOns may already provide the required grid component.

- `2026-08-27T05:44:59Z`: Related viewer-environment enhancements: #24, #25, and #26.
- `2026-08-27T06:26:35Z`: Added an optional model-space reference grid with a Renderer inspector toggle. xcb build and xcb test pass.

---

## 25: Add a skybox to the 3D viewer

+++
status: open
priority: medium
kind: feature
labels: effort:m
created: 2026-08-27T03:38:12Z
updated: 2026-08-27T05:44:59Z
+++

Add skybox support to the 3D viewer. MetalSprocketsAddOns may already provide the required skybox component.

- `2026-08-27T05:44:59Z`: Related viewer-environment enhancements: #24, #25, and #26.
- `2026-09-10T00:05:24Z`: Confirmed MetalSprocketsAddOns provides SkyboxRenderPipeline (cubemap) and EquirectangularSkyboxRenderPipeline (lat-long panorama), both taking projection/camera matrices + MTLTexture. Punting on integration decisions: (1) texture source — bundled default HDRI (needs a licensed asset), user-picked image, or procedural gradient; (2) inspector UI for toggle/picker/brightness; (3) composition — the skybox must render beneath splats in both the single-cloud (5 pipelines with per-pass load actions) and multi-cloud paths, which #49 wants to unify first. Unblocker: pick the texture source and whether to wait for #49; the render-pass wiring is straightforward after that.

---

## 26: Add axis lines to the 3D viewer

+++
status: closed
priority: medium
kind: enhancement
labels: effort:s
created: 2026-08-27T03:38:12Z
updated: 2026-08-27T06:29:00Z
closed: 2026-08-27T06:29:00Z
+++

Add optional axis lines to the 3D viewer. MetalSprocketsAddOns may already provide the required axis component.

- `2026-08-27T05:44:59Z`: Related viewer-environment enhancements: #24, #25, and #26.
- `2026-08-27T06:29:00Z`: Added optional red, green, and blue model-space axis lines with a Renderer inspector toggle. swiftlint, xcb build, and xcb test pass.

---

## 27: Show COLMAP markers in the main view

+++
status: open
priority: medium
kind: enhancement
labels: effort:m
created: 2026-08-27T03:39:07Z
updated: 2026-08-27T05:44:48Z
+++

Display the COLMAP markers directly in the main 3D view so they are visible alongside the loaded scene.

- `2026-09-10T00:03:16Z`: Assessed: COLMAP rendering exists standalone (ColmapViewerView window with its own orbit camera, point cloud + frustum line elements). Integrating markers into the main splat view needs decisions first: (1) how a document finds its COLMAP data (sidecar sparse/ folder next to the splat, explicit picker, or remembered association), (2) which markers to show (camera frustums, sparse points, both), (3) coordinate alignment with the splat sceneTransform (COLMAP convention is +Z forward/+Y down), (4) toggle placement in the inspector. Punting: implementation is mechanical once those are picked. Unblocker: answer 1-4 (or say 'sidecar folder, frustums only, reuse ColmapGeometry transform, Render inspector toggle' and I'll build exactly that).

---

## 28: Load screen shows the wrong app name

+++
status: closed
priority: medium
kind: bug
labels: effort:xs
created: 2026-08-27T03:39:53Z
updated: 2026-08-27T06:14:18Z
closed: 2026-08-27T06:14:18Z
+++

The load/splash screen identifies the app as “Gaussian Splats” instead of “Radiance.”

Expected: The screen displays “Radiance.”

Actual: The screen displays the old app name.

---

## 29: Show Bounding Boxes is broken

+++
status: closed
priority: medium
kind: bug
labels: effort:s
created: 2026-08-27T03:44:02Z
updated: 2026-08-27T06:24:21Z
closed: 2026-08-27T06:24:21Z
+++

The Show Bounding Boxes control no longer displays bounding boxes in the 3D view. This appears to be a regression.

Expected: Enabling the control shows bounding boxes.

Actual: Enabling the control has no visible effect.

- `2026-08-27T05:44:59Z`: Related to #21: both are regressions in debug/visualization controls.
- `2026-08-27T06:24:21Z`: Use the overlay's current geometry directly so projection never uses a stale zero viewport. No UI regression target exists; xcb build and xcb test pass.

---

## 30: Use the animated app icon consistently

+++
status: closed
priority: medium
kind: enhancement
labels: effort:xs
created: 2026-08-27T03:45:18Z
updated: 2026-08-27T06:16:30Z
closed: 2026-08-27T06:16:30Z
+++

Use the animated Radiance icon consistently across branded screens, including About, Welcome, and other app-name or launch surfaces.

---

## 31: Tighten the sidebar and inspector UI

+++
status: new
priority: medium
kind: enhancement
labels: needs-info, effort:m
created: 2026-08-27T03:45:53Z
updated: 2026-08-27T05:44:48Z
+++

Improve the sidebar and inspector layout so controls use space more efficiently and the visual hierarchy, alignment, and spacing are consistent.

---

## 32: Add procedural splat generation window

+++
status: open
priority: medium
kind: feature
labels: effort:l
created: 2026-08-27T03:47:41Z
updated: 2026-08-27T05:44:48Z
+++

Add a splat generation window for creating procedural Gaussian splat assets. Include spheres, toruses, realistic clouds, and multiple color options.

- `2026-09-10T00:07:00Z`: Assessed in the autonomous run: needs design before code — (1) generator algorithms and parameters (sphere/torus are tractable; 'realistic clouds' implies noise-based density and opacity/scale distributions that need iteration), (2) parameter window UX, (3) output path: viewing in a new document is easy, but saving generated splats depends on splat writing which doesn't exist yet (#39/.ply export only via convertedURL). Punting per the obvious-solutions-only constraint. Unblocker: decide the initial generator set + parameters and whether output is view-only or written to file (which format), then this can be built in a dedicated session.

---

## 33: Add a COLMAP structure-from-motion tool

+++
status: open
priority: medium
kind: feature
labels: effort:xl
created: 2026-08-27T03:47:41Z
updated: 2026-08-27T05:44:59Z
+++

Add a COLMAP tool that accepts a batch of photos via drag and drop and runs structure-from-motion to produce COLMAP reconstruction data.

- `2026-08-27T05:44:59Z`: Related to #34: this produces the COLMAP data consumed by the web-service generation workflow.

---

## 34: Generate splats from COLMAP data using the web service

+++
status: new
priority: medium
kind: feature
labels: needs-info, effort:l
created: 2026-08-27T03:47:41Z
updated: 2026-08-27T05:44:59Z
+++

Add a workflow that takes COLMAP reconstruction data and its source photos, uploads them to the web service, and returns a generated Gaussian splat.

- `2026-08-27T05:44:59Z`: Related to #33: this consumes the COLMAP reconstruction produced by that tool.

---

## 35: Save splat camera metadata in an extended attribute

+++
status: open
priority: medium
kind: enhancement
labels: effort:s
created: 2026-08-27T03:50:07Z
updated: 2026-08-27T05:44:59Z
+++

When the user saves a splat, serialize the current camera information as JSON and store it in a file extended attribute.

- `2026-08-27T05:44:59Z`: Related to #36: both persist additional metadata when saving a splat.
- `2026-09-09T23:04:06Z`: Related: #53 covers remembering all per-document settings (xattr or central DB); this issue is the camera-specific xattr variant. The .splatcamera sidecar (#59, implemented) already defines the JSON format both should reuse.
- `2026-09-10T00:02:52Z`: Assessed for implementation: the stated trigger ('when the user saves a splat') doesn't exist yet — splat documents are read-only (#39 open), and the only camera persistence paths today are the .splatcamera sidecar (#59) and Share Camera export. Punting: needs two decisions before coding: (1) what event writes the xattr (debounced camera change, document close, or an explicit menu action), and (2) whether to commit to xattr storage now given #53 leaves xattr-vs-central-DB open. Unblocker: pick the write trigger, or fold this into #53's storage decision.

---

## 36: Save a splat preview in an extended attribute

+++
status: open
priority: medium
kind: enhancement
labels: effort:m
created: 2026-08-27T03:50:07Z
updated: 2026-08-27T05:44:59Z
+++

Store a preview image in an extended attribute when saving a splat so the file can expose a representative thumbnail without rendering it again.

- `2026-08-27T05:44:59Z`: Related to #35: both persist additional metadata when saving a splat.
- `2026-09-10T00:03:33Z`: Same blocker as #35 (see today's comment there): splat documents are read-only (#39 open), so there is no save event to hook. Also needs a decision on the consumer: a preview xattr is only useful if something reads it (e.g. a QLThumbnail extension — note #40's finding that Apple claims .ply, though thumbnails for .spz/.splat/.sog would work). Punting. Unblocker: pick the write trigger (render-on-open, document close, explicit action) and confirm the intended consumer, or fold into #53's storage decision.

---

## 37: Export splats in another format

+++
status: new
priority: medium
kind: feature
labels: needs-info, effort:l
created: 2026-08-27T03:50:07Z
updated: 2026-08-27T05:44:59Z
+++

Add an export workflow that lets users save the current splat in a different supported file format.

- `2026-08-27T05:44:59Z`: Related to #39: alternate-format export depends on writable splat formats.

---

## 38: Add splat selection and editing

+++
status: open
priority: medium
kind: feature
labels: effort:xl
created: 2026-08-27T03:51:54Z
updated: 2026-08-27T05:44:59Z
+++

Add bounding-box and marquee selection for individual splats. Selected splats can be deleted or assigned custom attributes.

This requires supporting work in the MetalSprocketsGaussianSplats library.

- `2026-08-27T05:44:59Z`: Related to #42: spreadsheet inspection may expose selection and editable attributes.

---

## 39: Make splat documents read-write

+++
status: open
priority: medium
kind: feature
labels: effort:xl
created: 2026-08-27T03:53:26Z
updated: 2026-08-27T05:44:59Z
+++

Allow the document view to modify and save splat documents instead of treating them as read-only. Writing must support every splat format that the app can read.

This requires format-writing support in the MetalSprocketsGaussianSplats library.

- `2026-08-27T05:44:59Z`: Related to #37: read-write document support enables alternate-format export.

---

## 40: .ply files do not preview in Quick Look

+++
status: open
priority: medium
kind: bug
labels: effort:m
created: 2026-08-27T03:54:16Z
updated: 2026-08-27T05:44:59Z
+++

Quick Look does not render previews for .ply splat files.

Expected: Selecting a supported .ply file in Finder shows a Radiance preview.

Actual: No Quick Look preview is available.

- `2026-08-27T05:45:00Z`: Related to #41: both concern Quick Look support and document type registration.
- `2026-08-27T06:22:05Z`: Reproduced with qlmanage against a valid test-grid.ply after building and registering the extension: Quick Look reported that the file did not produce a preview. Verified mdls resolves .ply as public.polygon-file-format and the built extension advertises that exact UTI. Also tested an app-owned exported PLY UTI; Launch Services continued resolving .ply to the system UTI, so the change was reverted. Unblocker: capture QuickLookUI/ExtensionKit logs from Finder on a machine with the installed app to determine whether the extension is not selected or is failing during launch.
- `2026-09-09T23:58:24Z`: Root cause identified via on-machine logs (the unblocker from the last punt): Quick Look routes .ply previews to Apple's HydraQLPreviewExtension (/System/Library/PrivateFrameworks/Hydra.framework/Plugins/HydraQLPreviewExtension.appex), whose QLSupportedContentTypes includes public.polygon-file-format. Hydra runs, fails on gaussian-splat PLYs ('did not produce any preview'), and QL does not fall back to our registered extension (verified registered via pluginkit; .spz/.splat/.sog are unaffected because Apple claims only the mesh formats). No supported API overrides the system's preview-provider selection for a system UTI. Punting: OS-level extension selection, not fixable in this repo. Options: file Apple Feedback requesting fallback/override, or close as blocked-by-OS.

---

## 41: .sog files use a ZIP icon and are not associated with Radiance

+++
status: closed
priority: medium
kind: bug
labels: effort:m
created: 2026-08-27T03:54:16Z
updated: 2026-08-27T06:23:49Z
closed: 2026-08-27T06:23:49Z
+++

.sog files appear with a ZIP archive icon, do not preview in Quick Look, and do not open in Radiance by default.

Expected: .sog files use the app’s document icon, provide a Quick Look preview, and open in Radiance by default.

Actual: Finder treats them as ZIP archives.

- `2026-08-27T05:45:00Z`: Related to #40: both concern Quick Look support and document type registration.

---

## 42: Add spreadsheet mode for splat inspection

+++
status: open
priority: medium
kind: feature
labels: effort:l
created: 2026-08-27T04:03:21Z
updated: 2026-08-27T05:44:59Z
+++

Add a spreadsheet-style inspection mode that displays individual splats and their attributes in rows and columns for browsing, sorting, and inspection.

- `2026-08-27T05:44:59Z`: Related to #38: spreadsheet inspection may expose selection and editable attributes.
- `2026-09-10T00:07:15Z`: Assessed in the autonomous run: needs design first — (1) surface: separate window, document tab, or inspector pane; (2) columns: SparkSplat stores packed/quantized attributes (position, scale, rotation quat, color/opacity, SH) — show raw packed values, decoded floats, or both; (3) scale: clouds run to millions of splats, so the table needs lazy paging from the splat buffer and a strategy for full-set sort-by-column; (4) coupling to #38 (selection/editing) which is effort:xl. Punting per the obvious-solutions-only constraint. Unblocker: pick surface + initial column set and whether v1 is read-only; a read-only lazy Table over decoded attributes is then a mechanical build.

---

## 43: Add a splat color image view

+++
status: new
priority: medium
kind: feature
labels: needs-info, effort:m
created: 2026-08-27T04:03:21Z
updated: 2026-08-27T05:44:49Z
+++

Add a window or view that visualizes the colors of all splats as an image for inspecting the cloud’s color distribution and data.

---

## 44: Spherical Harmonics control has no effect

+++
status: open
priority: medium
kind: bug
labels: effort:m, area:rendering
created: 2026-08-27T06:51:53Z
updated: 2026-09-09T23:03:58Z
+++

The Spherical Harmonics control does not change the rendered splat appearance.

Expected: Toggling the control enables or disables spherical-harmonic rendering.

Actual: The rendered output does not change.

- `2026-09-09T23:59:53Z`: Root cause: in MetalSprocketsGaussianSplats' SparkSplatRenderPipeline, vertexShader/fragmentShader are @MSState-persisted and updatedShaders() recompiles only when lastUseBoundingBox changes. The use_sh function constant stays baked from the first frame, so per-frame changes to useSphericalHarmonics never rebuild the PSO (and the shDegree runtime binding is skipped by reflection when use_sh was baked false). Radiance's plumbing (toggle -> viewModel -> pipeline configuration) is correct. Punting: fix belongs in the dependency repo (track lastUseSH alongside lastUseBoundingBox in updatedShaders and recompile when it changes), then bump the package in Radiance. Unblocker: apply that change in MetalSprocketsGaussianSplats.
- `2026-09-10T00:28:34Z`: Fix implemented in MetalSprocketsGaussianSplats (local commit a2d0a2a3 'Recompile shaders when the use_sh function constant drifts'): SparkSplatRenderPipeline tracks lastUseSH alongside lastUseBoundingBox and recompiles on drift; StochasticSplatRenderPipeline gains the same updatedShaders() pattern. Built clean; package test suite green apart from a pre-existing PointSplatComputePass failure also present on main. Remaining to close this issue: push the dependency commit, update Radiance's package pin, and verify the toggle in-app.

---

## 45: FPS display is always zero

+++
status: closed
priority: medium
kind: none
created: 2026-08-27T06:51:53Z
updated: 2026-09-09T21:03:17Z
closed: 2026-09-09T21:03:17Z
+++

The renderer FPS readout remains at 0 while the scene is actively rendering.

Expected: The readout reports the current measured frame rate.

Actual: It always displays 0.

- `2026-09-09T21:03:17Z`: Verified working; closing.

---

## 46: Remove manual sorting controls

+++
status: closed
priority: medium
kind: none
created: 2026-08-27T06:51:53Z
updated: 2026-09-09T23:03:58Z
closed: 2026-09-09T23:03:58Z
+++

The Enable Sorting toggle and Sort Now button are obsolete and should no longer appear in the renderer inspector.

- `2026-09-09T23:03:58Z`: Already done: the Sorting section (Enable Sorting toggle, Sort Now button, sort stats) was removed from the Render inspector in commit 'Polish inspector panes'.

---

## 47: Bounding-box overlay renders no visible wireframe

+++
status: open
priority: medium
kind: bug
labels: effort:m, area:rendering
created: 2026-08-27T07:09:36Z
updated: 2026-09-09T23:03:58Z
+++

Enabling bounding boxes produces no visible wireframe in the scene. The SwiftUI Canvas overlay is present, but the failure stage is not yet confirmed.

Investigate with focused diagnostics for bounding-box count and values, viewport size, clip-space W values, and projected-corner count before changing layout or rendering code.

Expected: Enabling bounding boxes draws the cloud bounds over the rendered scene.

Actual: No bounding-box lines appear.

- `2026-09-10T00:02:10Z`: Investigated statically: simulated BoundingBoxWireframe's exact projection math (PerspectiveProjection standard depth, camera at +5Z, xRotation(pi) scene transform, unit box) — all 8 corners project on-screen, clip.w guard and screen-bounds guards pass. Data plumbing also checks out: single mode computes bounds via descriptor.computeBounds() and guards showBoundingBoxes/boundsSize; multi mode fills bounds async via computeBoundsForLoadedClouds. Punting: failure stage still unconfirmed without runtime inspection. Unblocker: with the app running and boxes enabled, log boundingBoxInfos.count and one projected corner in SplatBoundingBoxOverlayView (and confirm GeometryReader proxy.size is nonzero) to pin whether infos are empty, the overlay is zero-sized, or the Canvas is occluded by the Metal layer.

---

## 48: Replace SplatView with a unified RenderView for every renderer

+++
status: closed
priority: medium
kind: none
created: 2026-08-27T07:09:59Z
updated: 2026-08-27T13:38:22Z
closed: 2026-08-27T13:38:22Z
+++

Remove all Radiance rendering paths that use SplatView.

Implement every renderer mode through Radiance-owned RenderView composition so splats, the reference grid, axis lines, frame timing, and other scene elements share the same rendering surface. Multi-cloud rendering must follow the same architecture.

Acceptance criteria:
- No SplatView usage remains in Radiance.
- Every renderer mode uses a Radiance-owned RenderView.
- Grid and axis controls work in every renderer mode.
- Single-cloud and multi-cloud rendering use the unified composition architecture.

---

## 49: Single- and multi-cloud documents use divergent rendering paths

+++
status: open
priority: high
kind: task
labels: rendering, architecture, effort:l, area:rendering, area:architecture
created: 2026-08-27T13:39:30Z
updated: 2026-09-09T23:03:59Z
+++

Single-cloud documents and multi-cloud scenes enter different renderer implementations even though both already provide an array of GPU splat clouds to SplatRenderView. This duplicates render-pass composition, sorting ownership, debug rendering, scene-guide handling, and frame lifecycle behavior. Features can consequently work differently depending on document type; renderer selection currently applies only to single-cloud rendering, while bounds culling applies only to multi-cloud rendering.

The divergence remains after #48: both paths now use Radiance-owned RenderView composition, but SingleCloudGuidedRenderView and MultiCloudRenderView still independently implement that composition.

Expected: one-cloud and many-cloud documents use the same rendering implementation and differ only in document/UI preparation and capabilities that are inherently scene-specific. A one-cloud document should pass a one-element cloud collection through the same render path used by a scene.

Actual: SplatRenderingView branches on SplatContentMode. Single mode owns renderer-specific resources and dispatches among five pipelines; multi mode requires an externally owned AsyncSortManager and always uses the multi-cloud Spark pipeline. Debug rendering is also split into separate single- and multi-cloud paths.

## Proposed fix (per user)
Make the shared renderer collection-based: route single-cloud documents through the multi-cloud implementation with one cloud, consolidate render-pass composition and sorting/resource ownership, and keep document-specific UI and scene preparation outside the renderer. Preserve correct global transparency ordering across all clouds.

Acceptance criteria:
- Single-cloud rendering passes a one-element cloud collection through the same core render implementation as multi-cloud rendering.
- Normal, debug, grid, axes, bounding boxes, FPS tracking, spherical harmonics, clear color, projection updates, and drawable-size handling have one shared composition path.
- Renderer capabilities are explicit and behave consistently for one or many clouds; unsupported combinations are disabled or clearly represented in the UI.
- Sorting has one ownership/lifecycle model and maintains one global index order across the collection.
- Document-mode branching remains only for UI, document data preparation, interaction, and scene-specific controls.
- Tests or focused checks cover equivalent output/configuration for a one-cloud document and a one-cloud scene.

- `2026-09-09T23:51:06Z`: Assessed for the autonomous run: the unification spans SplatRenderView (919 lines, five single-cloud pipelines), MultiCloudRenderView, sorting ownership (AsyncSortManager lifecycle), debug paths, and capability-driven UI. Punting: effort:l redesign with wide blast radius, not the obvious/low-risk fix this run is scoped to. Unblocker: split into subtasks (e.g. 1. collection-based core renderer, 2. route single-cloud through it, 3. consolidate debug/guides, 4. capability surfacing) or green-light a dedicated session for the full refactor.

---

## 50: Inspector content is cramped and clipped at narrow widths on iPad

+++
status: closed
priority: medium
kind: bug
labels: bug, ui, effort:m, area:ui
created: 2026-09-09T19:51:15Z
updated: 2026-09-09T23:48:19Z
closed: 2026-09-09T23:48:19Z
+++

The inspector column (min width 200) is too narrow for its content on iPad. Observed in the simulator (iPad Pro 13-inch, iOS 27):

- Tab picker truncates labels: 'Cam…', 'Rend…', 'Analy…'
- Camera Position row clips the last field; axis labels overflow
- 'Keep cloud in frame' toggle label wraps awkwardly
- Angle of view H/V segmented control plus value crammed onto one line

Expected: inspector content remains readable and fully visible at the minimum column width.

## Proposed fix (per schwa)
Raise the inspector minimum column width to fit the content, and make the inspector controls adaptive so they reflow gracefully at narrow widths.

- `2026-09-09T23:48:19Z`: Camera controls reworked in Interaction3D: fields flex to divide the sidebar width, native rounded borders, AOV slider behind a popover, forced small control size removed.

---

## 51: Guides overlay draws on top of splats

+++
status: closed
priority: low
kind: none
labels: ui, rendering
created: 2026-09-09T20:23:05Z
updated: 2026-09-09T20:34:23Z
closed: 2026-09-09T20:34:23Z
+++

After standardizing scene guides into a single trailing SceneGuidesRenderPass shared by all renderers, the grid and axis lines composite over the splat output. Previously (Spark CPU/GPU, Stochastic) the grid was drawn before the splats, so splats alpha-blended over it. Guides-first ordering is currently impossible for tile and point because their passes clear the drawable internally (see MetalSprocketsGaussianSplats issue on load-action control).

- `2026-09-09T20:34:23Z`: Guides now draw first and all splat passes load instead of clearing (MSGS colorLoadAction), so splats composite over the grid/axes as before.

---

## 52: Point splat renderer passes a constant frameIndex and omits reprojection/supersampling configuration

+++
status: open
priority: low
kind: bug
labels: effort:s, area:rendering
created: 2026-09-09T20:23:05Z
updated: 2026-09-09T23:03:59Z
+++

SplatRenderView calls PointSplatRenderPipeline with frameIndex: 0 every frame and does not pass the supersampling, pointsPerThread, or reprojection options that the MetalSprocketsGaussianSplats demo (SplatView) wires up. Any temporal logic keyed off frameIndex never advances, and the renderer runs with defaults rather than the demo's tuned configuration.

---

## 53: Remember per-document settings across sessions

+++
status: open
priority: medium
kind: feature
labels: effort:m
created: 2026-09-09T20:30:04Z
updated: 2026-09-09T23:03:59Z
+++

Viewer settings (renderer, camera, background color, model orientation, inspector state, etc.) reset every time a document is reopened. Settings should persist per document.

## Proposed fix (per schwa)
Store settings either in an extended attribute (xattr) on the document file or in a central database keyed by document.

- `2026-09-09T20:50:07Z`: Strongly related to #59: whichever storage wins (xattr, database, or sidecar), use the same JSON format as #59's sidecar — based on SplatScene.CameraState (camera matrix, FOV, mode, clip planes) plus model transform.
- `2026-09-09T23:04:06Z`: Related: #35 (camera xattr) is a narrower slice of this.
- `2026-09-10T00:05:40Z`: Assessed in the autonomous run: punting because the issue's own proposed fix leaves the core decision open (xattr on the file vs central database keyed by document — sandboxed writes to source-file xattrs also differ in behavior across cloud storage/backups). The exact settings set to persist is also unspecified. #35 and #36 were punted into this decision today. Unblocker: pick storage (recommend central store keyed by file bookmark/URL, avoiding xattr write-permission issues on read-only documents) and list the settings to persist; the plumbing via SplatViewModel is then mechanical.

---

## 54: Axis lines extend past the horizon

+++
status: open
priority: low
kind: bug
labels: ui, rendering, effort:s, area:ui, area:rendering
created: 2026-09-09T20:30:16Z
updated: 2026-09-09T23:03:59Z
+++

With the reference grid and axis lines both enabled, the X (red) and Z (blue) axis lines extend above the horizon into the sky, and the Y (green) axis runs the full viewport height. The grid stops at the horizon, so the axis lines look detached from the scene.

Expected: axis lines end at the horizon, at least when the grid is on (they may just look odd combined with the grid).

Screenshot: iPad, Point renderer, dark background, grid + axes on.

---

## 55: Grid and axis lines are aliased

+++
status: open
priority: low
kind: enhancement
labels: ui, rendering, effort:m, area:rendering
created: 2026-09-09T20:37:30Z
updated: 2026-09-09T23:03:59Z
+++

The reference grid and axis lines render with visible aliasing (jagged/shimmering lines), especially at grazing angles where grid lines converge toward the horizon.

## Proposed fix (per schwa)
Render the guides pass with MSAA if possible.

---

## 56: Bundle display name shows Radiance-Viewer instead of Radiance

+++
status: open
priority: low
kind: task
labels: effort:xs, area:ui
created: 2026-09-09T20:39:40Z
updated: 2026-09-09T23:03:59Z
+++

The status bar and app switcher show 'Radiance-Viewer' as the app name.

## Proposed fix (per schwa)
Set the bundle display name to just 'Radiance'.

---

## 57: About box shows the wrong title

+++
status: open
priority: low
kind: bug
labels: effort:xs, area:ui
created: 2026-09-09T20:43:43Z
updated: 2026-09-09T23:03:59Z
+++

The About window's title is wrong (shows the bundle/product name rather than the app name Radiance).

---

## 58: Grid and axis lines missing in debug mode

+++
status: open
priority: low
kind: bug
labels: effort:s, area:rendering
created: 2026-09-09T20:48:25Z
updated: 2026-09-09T23:03:59Z
+++

With Enable Debug Mode on, the reference grid and axis lines are not rendered even when Show Reference Grid / Show Axis Lines are enabled. The debug render path (SingleCloudDebugRenderView) does not draw the scene guides pass.

---

## 59: Load a sidecar document with camera and model transform when opening a splat file

+++
status: closed
priority: medium
kind: feature
created: 2026-09-09T20:49:06Z
updated: 2026-09-09T20:54:28Z
closed: 2026-09-09T20:54:28Z
+++

Opening a splat file always starts with default camera and model transform. There is no way to keep viewing state alongside a splat file.

Desired: when loading a file, look for a sidecar document next to it containing camera and model transform info, and use it to populate the viewer state. Define a new UTType for the sidecar file. Related: #53 (per-document settings persistence) and the new camera share JSON (SplatScene.CameraState Transferable), which could share the same format.

- `2026-09-09T20:50:07Z`: Strongly related to #53: use the same JSON format for the sidecar as for per-document settings persistence, based on SplatScene.CameraState plus model transform.
- `2026-09-09T20:54:28Z`: Implemented: com.schwa.splatcamera UTType (.splatcamera, JSON), sidecar loaded next to splat files populating camera mode, clips, FOV, matrix, and optional model rotation. Share Camera exports the same format. Not covered: xattr/central-db persistence (#53), model translation/scale, sandboxed sibling reads for user-picked files.

---

## 60: Export Screenshot sheet defaults width and height to 0

+++
status: closed
priority: medium
kind: bug
labels: effort:s, area:ui
created: 2026-09-09T21:08:23Z
updated: 2026-09-09T23:53:47Z
closed: 2026-09-09T23:53:47Z
+++

Opening the Export Screenshot sheet shows Width 0 and Height 0 instead of the current viewport size (times display scale), and there is no preview ('No Preview'). Observed on iPad with the tomatoes sample loaded.

---

## 61: Export Screenshot sheet action buttons are badly laid out

+++
status: open
priority: low
kind: bug
labels: effort:s, area:ui
created: 2026-09-09T21:08:23Z
updated: 2026-09-09T23:03:59Z
+++

The Cancel / Copy / Save… controls at the bottom of the Export Screenshot sheet are cramped into one ad-hoc row with mixed styles: Cancel is a bare text button, Copy is icon+text, Save… is a small prominent capsule. They neither follow alert/sheet button conventions nor align with the Width/Height fields above. Observed on iPad.

---

## 62: Render continuously even when nothing changes; add on-demand rendering toggle

+++
status: open
priority: medium
kind: feature
labels: rendering, performance, effort:m, area:rendering, area:performance
created: 2026-09-09T21:22:48Z
updated: 2026-09-09T23:03:59Z
+++

The MTKView runs in continuous mode, redrawing at 60 fps even when the scene is static, wasting power (notably on iPad).

Desired: render on demand by default — only when the camera, model transform, or render parameters change — with a toggle (Render pane) to switch back to continuous rendering. Renderers that accumulate over time (stochastic, point splat reprojection) need continuous frames while converging, so the on-demand mode must account for them. Related: MetalSprocketsGaussianSplats has an issue about rendering a new frame only when render-affecting inputs change.

- `2026-09-10T00:06:26Z`: Assessed: MetalSprocketsUI's RenderView supports paused + setNeedsDisplay MTKView modes via .metalIsPaused/.metalEnableSetNeedsDisplay environment modifiers, but exposes no way for the host app to request a frame when render inputs change — the MTKView and its delegate are fully encapsulated, and the update closure never marks the view dirty. On-demand mode therefore needs dependency work first: an invalidation API on RenderView (e.g. an environment-injected draw-request token or auto-redraw when the content closure's captured inputs change), matching the related MetalSprocketsGaussianSplats issue this report mentions. Convergence-aware continuous frames for stochastic/point-splat accumulation layer on top of that. Punting: cross-repo design. Unblocker: add the RenderView invalidation API in MetalSprockets, then wiring the Radiance toggle + change detection is straightforward.

---

## 63: SingleCloudGuidedRenderView allocates GPUSortResources on every body eval

+++
status: new
priority: high
kind: bug
labels: rendering, performance, area:rendering, area:performance
created: 2026-09-10T02:42:56Z
+++

SingleCloudGuidedRenderView.init creates GPUSortResources via _resources = State(initialValue: try GPUSortResources(device:capacity:)). SwiftUI evaluates the initialValue expression on every init (every parent body evaluation) and keeps only the first result, so the GPUSortResources allocation (scratch + output buffers x slotCount, sized to splat count) runs and is thrown away on each body eval.

Expected: sort resources are allocated once per cloud and reused across body evaluations.

Actual: under sustained high-frequency body evals (e.g. turntable momentum drags or the rotation cube), the per-eval allocation of GPU buffers stalls/hangs the UI.

Location: Radiance/SplatDocuments/Shared/SplatRenderView.swift (SingleCloudGuidedRenderView.init around the '_resources = State(initialValue:)' line; SingleCloudDebugRenderView has the same pattern). SplatViewModel previously had the same issue with AsyncSortManager/CPUSplatRadixSorter (now removed).

Fix: make resources lazy — hold @State private var resources: GPUSortResources? = nil, create it once in .task/onAppear (or .task(id:) keyed to the cloud), and guard rendering until it exists. Apply to both SingleCloudGuidedRenderView and SingleCloudDebugRenderView.

---

## 64: Audit and remove State(initialValue:) init pattern in views

+++
status: new
priority: medium
kind: task
labels: swiftui,performance,architecture,area:swiftui,area:performance
depends: 63
created: 2026-09-10T02:43:29Z
+++

State(initialValue:) in a view's init is an anti-pattern: SwiftUI evaluates the expression on every init (every parent body evaluation) and discards all but the first result. When the initial value is expensive (allocating GPU buffers, creating model objects, doing IO), that cost is paid on every body eval, not once. It also hides the real initialization point and makes lifetimes hard to reason about.

Expected: view state is created lazily and once — via @State default initializers, .task/.onAppear for expensive/failable resources (keyed with .task(id:) when it must rebuild), or an @Observable model owned higher up.

Actual: several views build state eagerly in init with State(initialValue:), including expensive allocations.

Current occurrences (rg 'State(initialValue:'):
- SplatRenderView.swift:263 SingleCloudGuidedRenderView — GPUSortResources (see #63)
- SplatRenderView.swift:473 SingleCloudDebugRenderView — GPUSortResources (see #63)
- SplatDocumentContentView.swift:117 — SplatViewModel (cheap-ish, but recreated expression per eval)
- ScreenshotSheet.swift:62-63 — width/height Ints (cheap; acceptable, but note the earlier #60 timing bug came from capturing these at init)

Task: establish the house rule (prefer @State default init / .task over State(initialValue:) for anything non-trivial), fix the expensive cases (#63 covers the GPUSortResources ones), and review the cheap ones for the capture-timing hazard. Consider a lint note in AGENTS.md or a swiftlint custom rule.

---
