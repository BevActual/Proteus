//! Shared `wp_linux_dmabuf` global init for winit + DRM backends.

use smithay::{
    backend::{egl::EGLDevice, renderer::gles::GlesRenderer, renderer::ImportDma},
    reexports::wayland_server::DisplayHandle,
    wayland::dmabuf::DmabufFeedbackBuilder,
};

use crate::CompositorNext;

pub fn init_dmabuf_global(
    state: &mut CompositorNext,
    display_handle: &DisplayHandle,
    renderer: &GlesRenderer,
) -> Result<(), Box<dyn std::error::Error>> {
    if state.dmabuf_global.is_some() {
        return Ok(());
    }
    let formats: Vec<_> = renderer.dmabuf_formats().iter().copied().collect();
    if formats.is_empty() {
        eprintln!("proteus-compositor-next: dmabuf formats empty — SHM screencopy only");
        return Ok(());
    }

    let global = match EGLDevice::device_for_display(renderer.egl_context().display())
        .ok()
        .and_then(|d| d.try_get_render_node().ok().flatten())
    {
        Some(node) => {
            let feedback = DmabufFeedbackBuilder::new(node.dev_id(), formats).build()?;
            state
                .dmabuf_state
                .create_global_with_default_feedback::<CompositorNext>(display_handle, &feedback)
        }
        None => {
            eprintln!(
                "proteus-compositor-next: no EGL render node — dmabuf global v3 without feedback"
            );
            state
                .dmabuf_state
                .create_global::<CompositorNext>(display_handle, formats)
        }
    };
    state.dmabuf_global = Some(global);
    Ok(())
}
