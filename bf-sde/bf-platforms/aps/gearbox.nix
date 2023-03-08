{ lib, binutils-unwrapped, runCommand, stdenv, aps_gearbox,
  autoPatchelfHook, patchelf, boost172, openssl, bf-drivers }:

let
  python = bf-drivers.pythonModule;
in stdenv.mkDerivation {
  pname = "aps-bf2556-gearbox";
  src = runCommand "bf-aps-gearbox.tar.gz" {} ''
    ${binutils-unwrapped}/bin/ar x ${aps_gearbox.src}
    tar xf data.tar.gz ./usr
    mv usr $out
  '';
  inherit (aps_gearbox) version;
  buildInputs = [ python autoPatchelfHook patchelf boost172 openssl ];
  buildPhase = "true";
  installPhase = ''
    mkdir -p $out/bin $out/lib
    cp bin/* $out/bin
    cp lib/lib* $out/lib
    sitePath=$out/lib/${python.libPrefix}/site-packages
    mkdir -p $sitePath
    proto_dir=share/bf2556x/gearbox/proto
    ${python.pkgs.grpcio-tools}/lib/${python.libPrefix}/site-packages/grpc_tools/protoc.py -I $proto_dir \
      --python_out=$sitePath/ \
      --grpc_python_out=$sitePath/ \
      $proto_dir/gearbox.proto
    python -m compileall $sitePath
  '';
  preFixup = ''
    patchelf --remove-needed libboost_program_options.so.1.71.0 $out/bin/gearboxd
    patchelf --add-needed libboost_program_options.so.1.72.0 $out/bin/gearboxd
  '';
}
