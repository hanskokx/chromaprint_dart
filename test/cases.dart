/// The signals the reference fingerprints were recorded from.
typedef Case = ({
  String name,
  int rate,
  int channels,
  double seconds,
  double leadingSilence,
});

const cases = <Case>[
  (
    name: "mono_11025",
    rate: 11025,
    channels: 1,
    seconds: 20,
    leadingSilence: 0,
  ),
  (
    name: "stereo_11025",
    rate: 11025,
    channels: 2,
    seconds: 20,
    leadingSilence: 0,
  ),
  (
    name: "stereo_44100",
    rate: 44100,
    channels: 2,
    seconds: 20,
    leadingSilence: 0,
  ),
  (
    name: "mono_48000",
    rate: 48000,
    channels: 1,
    seconds: 20,
    leadingSilence: 0,
  ),
  (
    name: "stereo_22050",
    rate: 22050,
    channels: 2,
    seconds: 20,
    leadingSilence: 0,
  ),
  (
    name: "five_channel_44100",
    rate: 44100,
    channels: 5,
    seconds: 12,
    leadingSilence: 0,
  ),
  // Longer than fpcalc's 120 s limit, so the cut-off is tested.
  (
    name: "mono_11025_long",
    rate: 11025,
    channels: 1,
    seconds: 130,
    leadingSilence: 0,
  ),
  (name: "too_short", rate: 11025, channels: 1, seconds: 2, leadingSilence: 0),
  // Leading silence, which only algorithm 4 removes.
  (
    name: "leading_silence",
    rate: 11025,
    channels: 1,
    seconds: 12,
    leadingSilence: 1,
  ),
];
