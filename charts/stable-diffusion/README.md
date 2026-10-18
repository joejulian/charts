# stable-diffusion.cpp

Runs one image-generation server with explicit CPU and memory limits. Supply
model filenames in `args` and an existing PVC in `models.existingClaim`.
The chart mounts weights read-only and does not download models. `extraObjects`
can declare a retained, node-affine local PV and prebound PVC for existing files.

Use an immutable Vulkan image digest and request the device-plugin resource for
your GPU. Advertised sharing slots do not partition VRAM: reserving every slot
of a dedicated card prevents competing Kubernetes workloads from scheduling.
RAM limits constrain cgroup-accounted host memory, not the number of GPU bytes.
Size the budget against the node's other workloads and driver allocations.

The Deployment uses Recreate so upgrades cannot load two copies simultaneously.
Missing CPU or memory requests/limits are rejected by the values schema.
Keep each host service that previously ran these models disabled. Never raise
memory limits above safe node capacity simply to get a large request to finish.

Startup and readiness probes check the capabilities API; liveness checks the
listener so a slow request does not restart inference. The working directory
is `/sd.cpp`: older upstream images default to `/`, where relative LoRA
discovery encounters protected `/proc` files and makes capabilities return 500.
Validation should also inspect component paths, GPU backend, and cgroup limits. CI uses a small HTTP fixture to exercise installation and upgrade
without downloading weights or requiring a GPU. It also checks the container's
actual cgroup memory and CPU limits and the read-only model mount.
