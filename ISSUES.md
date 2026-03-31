## 1: Adopt MetalSprocketsGaussianSplats buffer pooling
status: new
priority: medium
kind: enhancement
labels: performance,dependencies
created: 2026-03-31T20:00:13.631105+00:00

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

