// r7 palliative — force YouTube (and other MSE sites) to H.264/AVC.
//
// Firefox on this device is SOFTWARE-decode only: droidian-quirks-hybris-gl sets
// layers.acceleration.disabled=true (enabling GPU accel breaks Firefox on Mali).
// VP9/AV1 software decode stutters on 1080p; H.264 is far lighter and stays smooth.
// Blocking WebM-via-MSE (kills VP9) and AV1 makes YouTube fall back to avc1/mp4.
//
// For true HARDWARE decode use the "YouTube (HW)" app (yt-dlp -> Clapper/droidvdec);
// browsers cannot reach the HW decoder on Halium (no VA-API).

pref("media.mediasource.webm.enabled", false); // block VP9 (WebM) over MSE
pref("media.av1.enabled",              false);  // block AV1
pref("media.mediasource.enabled",      true);   // keep MSE (H.264/mp4) working

// Halium has no working VA-API / HW video for Firefox. Firefox otherwise probes
// it (vaapitest -> renderDeviceFD fail) and enumerates /dev/video* on every play,
// which is flaky here. Force the pure-software decode path and stop the probing.
pref("media.hardware-video-decoding.enabled", false);
pref("media.ffmpeg.vaapi.enabled",            false);
pref("media.rdd-vpx.enabled",                 true);  // decode VP8/9 in RDD if it slips through
pref("media.navigator.mediadatadecoder_vpx_enabled", false);
