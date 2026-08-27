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
- `2026-08-27T06:16:46Z`: Rechecked the resolved MetalSprocketsGaussianSplats API. GPUSortedSplatRenderPipeline still accepts a single GPUSplatCloud, while this view needs one globally sorted index stream across multiple clouds for correct alpha compositing. Concrete unblocker remains a dependency API that GPU-sorts multiple clouds as one logical stream (or exposes a combined GPU cloud/buffer view).

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
status: open
priority: medium
kind: feature
labels: effort:s
created: 2026-08-27T03:36:07Z
updated: 2026-08-27T05:44:48Z
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

---

## 41: .sog files use a ZIP icon and are not associated with Radiance

+++
status: open
priority: medium
kind: bug
labels: effort:m
created: 2026-08-27T03:54:16Z
updated: 2026-08-27T05:45:00Z
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
status: new
priority: medium
kind: none
created: 2026-08-27T06:51:53Z
+++

The Spherical Harmonics control does not change the rendered splat appearance.

Expected: Toggling the control enables or disables spherical-harmonic rendering.

Actual: The rendered output does not change.

---

## 45: FPS display is always zero

+++
status: new
priority: medium
kind: none
created: 2026-08-27T06:51:53Z
+++

The renderer FPS readout remains at 0 while the scene is actively rendering.

Expected: The readout reports the current measured frame rate.

Actual: It always displays 0.

---
