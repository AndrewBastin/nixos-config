//! Which backend an Apple app draws with: Rune's native Metal backend (`metal-backend`, on by
//! default, and the default on macOS), or wgpu's.

use std::sync::atomic::{AtomicU8, Ordering};

/// The GPU backend an app draws with on macOS (`App::gpu_backend`) and iOS (`prewarm_gpu_on`, before
/// the first `embed::LayerHost`). Elsewhere wgpu picks one.
///
/// A Mac app that chooses neither draws with `Metal` when Rune's `metal-backend` feature is on (it
/// is by default), and with `Wgpu` when it's off; an iOS app draws with `Wgpu`. `Default` stays `Wgpu`; passing it to
/// `App::gpu_backend` opts out of the native backend.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum GpuBackend {
    /// wgpu's Metal backend.
    #[default]
    Wgpu,
    /// Rune's native Metal backend, with Rune's `metal-backend` feature; without it, wgpu.
    Metal,
}

const UNSET: u8 = 0;
const WGPU: u8 = 1;
const METAL: u8 = 2;

/// What the app chose: nothing yet, `Wgpu` or `Metal`.
#[cfg_attr(not(all(target_vendor = "apple", feature = "metal-backend")), allow(dead_code))]
static CHOSEN: AtomicU8 = AtomicU8::new(UNSET);

/// The backend an app that chooses none draws with: the native one on macOS with the feature.
const DEFAULT: GpuBackend = if cfg!(all(target_os = "macos", feature = "metal-backend")) { GpuBackend::Metal } else { GpuBackend::Wgpu };

/// Makes GPUs from now on with `backend`, process-wide. A `prewarm_gpu` running on another
/// backend starts over on this one.
#[cfg_attr(not(target_vendor = "apple"), allow(unused_variables))]
pub(crate) fn choose(backend: GpuBackend) {
    #[cfg(all(target_vendor = "apple", not(feature = "metal-backend")))]
    if backend == GpuBackend::Metal {
        eprintln!("rune: GpuBackend::Metal needs Rune's `metal-backend` feature; drawing with wgpu");
    }
    #[cfg(all(target_vendor = "apple", feature = "metal-backend"))]
    {
        let before = current();
        CHOSEN.store(match backend { GpuBackend::Wgpu => WGPU, GpuBackend::Metal => METAL }, Ordering::Relaxed);
        #[cfg(target_os = "macos")]
        if current() != before {
            crate::render::restart_prewarm();
        }
        #[cfg(not(target_os = "macos"))]
        let _ = before;
    }
}

fn chosen() -> Option<GpuBackend> {
    match CHOSEN.load(Ordering::Relaxed) {
        WGPU => Some(GpuBackend::Wgpu),
        METAL => Some(GpuBackend::Metal),
        _ => None,
    }
}

fn env() -> Option<String> {
    std::env::var("RUNE_GPU_BACKEND").ok()
}

#[cfg_attr(not(all(target_vendor = "apple", feature = "metal-backend")), allow(dead_code))]
/// The backend GPUs are made with: `RUNE_GPU_BACKEND` (`wgpu` or `metal`) over the app's
/// choice, over the default.
pub(crate) fn current() -> GpuBackend {
    resolve(env().as_deref(), chosen())
}

/// What `RUNE_GPU_LOG` calls the backend that draws.
pub(crate) fn label() -> &'static str {
    #[cfg(all(target_vendor = "apple", feature = "metal-backend"))]
    if current() == GpuBackend::Metal {
        return "rune backend";
    }
    "wgpu"
}

/// Whether a GPU for a compositor that wants `wanted` draws with wgpu instead of the native
/// backend: only when the native backend is the default, neither the app nor the environment
/// asked for it, and it lacks one of `wanted`'s features. Says so once.
#[cfg_attr(not(all(target_vendor = "apple", feature = "metal-backend")), allow(unused_variables))]
pub(crate) fn wgpu_for(wanted: wgpu::Features) -> bool {
    #[cfg(all(target_vendor = "apple", feature = "metal-backend"))]
    {
        let missing = wanted - crate::gpu::metal::FEATURES;
        if !missing.is_empty() && DEFAULT == GpuBackend::Metal && defaulted(env().as_deref(), chosen()) {
            static SAID: std::sync::Once = std::sync::Once::new();
            SAID.call_once(|| eprintln!("rune: the compositor wants {missing:?}, which Rune's Metal backend lacks; drawing with wgpu"));
            return true;
        }
    }
    false
}

/// Whether a GPU on `device` serves a compositor that wants `wanted`: false for a native
/// backend device when `wgpu_for(wanted)`.
pub(crate) fn serves(device: &wgpu::Device, wanted: wgpu::Features) -> bool {
    #[cfg(all(target_vendor = "apple", feature = "metal-backend"))]
    if crate::gpu::metal::raw_device(device).is_some() {
        return !wgpu_for(wanted);
    }
    let _ = (device, wanted);
    true
}

#[cfg_attr(not(all(target_vendor = "apple", feature = "metal-backend")), allow(dead_code))]
fn resolve(env: Option<&str>, chosen: Option<GpuBackend>) -> GpuBackend {
    match env {
        Some("metal") => GpuBackend::Metal,
        Some("wgpu") => GpuBackend::Wgpu,
        _ => chosen.unwrap_or(DEFAULT),
    }
}

/// Whether the backend is the default one, which neither the environment nor the app chose.
#[cfg_attr(not(all(target_vendor = "apple", feature = "metal-backend")), allow(dead_code))]
fn defaulted(env: Option<&str>, chosen: Option<GpuBackend>) -> bool {
    !matches!(env, Some("metal" | "wgpu")) && chosen.is_none()
}

#[cfg(test)]
mod tests {
    use super::{DEFAULT, GpuBackend, defaulted, resolve};

    #[test]
    fn the_environment_overrides_the_app() {
        assert_eq!(resolve(None, Some(GpuBackend::Metal)), GpuBackend::Metal);
        assert_eq!(resolve(Some("wgpu"), Some(GpuBackend::Metal)), GpuBackend::Wgpu);
        assert_eq!(resolve(Some("metal"), Some(GpuBackend::Wgpu)), GpuBackend::Metal);
        assert_eq!(resolve(Some(""), Some(GpuBackend::Metal)), GpuBackend::Metal);
    }

    #[test]
    fn an_app_that_chooses_wgpu_keeps_it_over_the_default() {
        assert_eq!(resolve(None, Some(GpuBackend::Wgpu)), GpuBackend::Wgpu);
        assert_eq!(resolve(None, None), DEFAULT);
        assert_eq!(resolve(Some("bogus"), None), DEFAULT);
        assert!(defaulted(None, None));
        assert!(!defaulted(None, Some(GpuBackend::Metal)));
        assert!(!defaulted(Some("metal"), None));
    }

    #[cfg(target_os = "macos")]
    #[test]
    fn macos_draws_with_the_native_backend_by_default_with_the_feature() {
        let expected = if cfg!(feature = "metal-backend") { GpuBackend::Metal } else { GpuBackend::Wgpu };
        assert_eq!(DEFAULT, expected);
    }
}
