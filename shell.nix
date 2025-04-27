{ pkgs ? import <nixpkgs> {} }:
let
  # Generating compressed fonts from BDF for use in embedded device.
  bdfont-data = pkgs.stdenv.mkDerivation rec {
    name = "bdfont-data";
    src = pkgs.fetchFromGitHub {
      owner = "hzeller";
      repo = "bdfont.data";
      rev = "v1.0";
      hash = "sha256-1QoCnX0L+GH8ufMRI4c9N6q0Jh2u3vDZn+YqnWMQe5M=";
    };
    postPatch = "patchShebangs src/make-inc.sh";
    buildPhase = "make -C src";
    installPhase = "mkdir -p $out/bin; install src/bdfont-data-gen $out/bin";
  };
in
pkgs.mkShell {
  buildInputs = with pkgs;
    [
      # Firmware dependencies
      pkgsCross.avr.buildPackages.gcc9
      otf2bdf
      avrdude
      bdfont-data

      # CAD for all printed parts
      openscad-unstable

      # CAM
      prusa-slicer
      #lightburn    # requrires unfree
    ];
    shellHook = ''
       unset QT_PLUGIN_PATH   # lightburn workaround
    '';
}
