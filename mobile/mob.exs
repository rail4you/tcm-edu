# mob.exs — Mob project configuration: plugin activation, plugin trust,
# styles, and build settings. Commit it — a clone without it activates no
# plugins, so their NIFs are left out of the native build.
#
# Machine-specific overrides (e.g. a local `mob_dir` checkout) go in
# mob.local.exs, which is gitignored and imported at the end of this file.
#
# OTP runtimes for Android and iOS are downloaded automatically by `mix mob.install`.

import Config

config :mob_dev,
  # Path to the mob library repo (native source files for iOS/Android builds).
  mob_dir: Path.join(File.cwd!(), "deps/mob"),

  # Path to your Elixir lib dir (e.g. ~/.local/share/mise/installs/elixir/1.18.4-otp-28/lib).
  elixir_lib: System.get_env("MOB_ELIXIR_LIB", :code.lib_dir(:elixir) |> to_string() |> Path.dirname()),

  # iOS devices and orientations, stamped into the built app's Info.plist
  # (they override ios/Info.plist). ios_target_devices: [:iphone, :ipad] runs
  # full-screen on iPad, resizes and joins Split View; [:iphone] runs iPad in
  # iPhone compatibility mode. An App Store app that has shipped iPad support
  # can't drop it in an update. ios_orientations (:all, :portrait or
  # :landscape) applies to iPhone; iPad always declares all four, since
  # iPadOS 26 rotates resizable apps freely.
  ios_target_devices: [:iphone, :ipad],
  ios_orientations: :all,

  # Open the app from <scheme>://... links: each arrives in Elixir as
  # {:link, %{url: url, source: :launch | :running}} (see Mob.Link). Takes a
  # native rebuild (mix mob.deploy --native). Schemes can't contain "_".
  # Also set android:launchMode="singleTask" on MainActivity in
  # android/app/src/main/AndroidManifest.xml (mob_dev refuses to build without it).
  # url_schemes: ["tcm-mobile"],

  # Several windows of the app on iPad (Split View, Stage Manager, the app
  # switcher), each with its own navigation, in one BEAM. Stamped into the
  # built app's Info.plist as UIApplicationSupportsMultipleScenes. iOS only;
  # Android ignores it. The per-window navigation needs a mob release with
  # Mob.Scene (not released yet, mob#184): keep false until then.
  multi_window: false

# No capability plugins are activated — this is a self-contained student app
# (camera/location/biometric plugins are removed from mix.exs accordingly).
config :mob, :plugins, []


if File.exists?(Path.join(__DIR__, "mob.local.exs")), do: import_config("mob.local.exs")
