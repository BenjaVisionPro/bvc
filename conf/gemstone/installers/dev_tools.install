# conf/bvc/dev_tools.install.sh
# Sourced helper. Defines: install_devtools_projects "<gitDir>"

install_devtools_projects() {

  gitDir="$1"
  : "${gitDir:?gitDir is required}"

  information_banner "Installing RemoteServiceReplication"
  installProject.stone "file:${gitDir}/RemoteServiceReplication/rowan/specs/RemoteServiceReplication.ston" \
    --projectsHome="${gitDir}" -D

  information_banner "Installing RowanClientServicesV3"
  installProject.stone "file:${gitDir}/RowanClientServicesV3/rowan/specs/RowanClientServices.ston" \
    --projectsHome="${gitDir}" --alias=RowanClientServicesV3 -D

  information_banner "Installing Sparkle"
  installProject.stone "file:${gitDir}/Sparkle/rowan/specs/Sparkle.ston" \
    --projectsHome="${gitDir}" -D

  information_banner "Installing gtoolkit-wireencoding"
  installProject.stone "file:${gitDir}/gtoolkit-wireencoding/rowan/specs/gtoolkit-wireencoding.ston" \
    --projectsHome="${gitDir}" -D

  information_banner "Installing gt4gemstone"
  installProject.stone "file:${gitDir}/gt4gemstone/rowan/specs/gt4gemstone.ston" \
    --projectsHome="${gitDir}" -D

  information_banner "Installing gtoolkit-remote"
  installProject.stone "file:${gitDir}/gtoolkit-remote/rowan/specs/gtoolkit-remote.ston" \
    --projectsHome="${gitDir}" -D
}