{ makeWrapper, symlinkJoin, taskmatter-bin }:

symlinkJoin {
  name = taskmatter-bin.name;
  paths = [ taskmatter-bin ];
  buildInputs = [ makeWrapper ];
  postBuild = ''
    makeWrapper $out/bin/taskmatter $out/bin/tm
  '';
}
