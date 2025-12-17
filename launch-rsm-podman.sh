#!/bin/bash

## Podman launch script for rsm-podman
## Supports both local builds and GHCR images

## create lock file path in user's home directory
if [ ! -d "${HOME}/.rsm-msba" ]; then
  mkdir -p "${HOME}/.rsm-msba"
fi
LOCK_FILE="${HOME}/.rsm-msba-launch.lock"

## check if lock file exists
if [ -f "${LOCK_FILE}" ]; then
  echo "---------------------------------------------------------------------------"
  echo "A launch script may already be running. To close the new session and"
  echo "continue with the previous session press q + enter. To continue with"
  echo "the new session and stop the previous session, press enter"
  echo "---------------------------------------------------------------------------"
  read contd
  if [ "${contd}" == "q" ]; then
    exit 1
  fi
  rm -f "${LOCK_FILE}"
fi

## create lock file
touch "${LOCK_FILE}"

## ensure lock file is removed when script exits
trap 'rm -f "${LOCK_FILE}"; exit' INT TERM EXIT

## set ARG_HOME to a directory of your choosing if you do NOT
## want to to map the podman home directory to your local
## home directory

## use the command below on to launch the container:
## ~/git/rsm-podman/launch-rsm-podman.sh -v ~

## to map the directory where the launch script is located to
## the podman home directory call the script_home function
script_home () {
  echo "$(echo "$( cd "$(dirname "$0")" ; pwd -P )" | sed -E "s|^/([A-z]{1})/|\1:/|")"
}

function launch_usage() {
  echo "Usage: $0 [-t tag (version)] [-v volume]"
  echo "  -t, --tag         Container image tag (version) to use"
  echo "  -v, --volume      Volume to mount as home directory"
  echo "  -s, --show        Show all output generated on launch"
  echo "  -h, --help        Print help and exit"
  echo ""
  echo "Example: $0 --tag 1.0.0 --volume ~/project_1"
  echo ""
  if [ "$1" != "noexit" ]; then
    exit 1
  fi
}

LAUNCH_ARGS="${@:1}"

## parse command-line arguments
while [[ "$#" > 0 ]]; do case $1 in
  -t|--tag) ARG_TAG="$2"; shift;shift;;
  -v|--volume) ARG_VOLUME="$2";shift;shift;;
  -s|--show) ARG_SHOW="show";shift;shift;;
  -h|--help) launch_usage;shift; shift;;
  *) echo "Unknown parameter passed: $1"; echo ""; launch_usage; shift; shift;;
esac; done

## change to some other path to use as default
# ARG_HOME="~/rady"
# ARG_HOME="$(script_home)"
ARG_HOME=""
IMAGE_VERSION="latest"
NB_USER="jovyan"
LABEL="rsm-podman"
HOSTNAME="${LABEL}"
NETWORK="rsm-network"
## Use GHCR image by default, or local test image with USE_LOCAL=1
USE_LOCAL="${USE_LOCAL:-0}"
if [ "$USE_LOCAL" == "1" ]; then
  IMAGE="localhost/${LABEL}"
else
  IMAGE="ghcr.io/radiant-ai-hub/${LABEL}"
fi
# Choose your timezone https://en.wikipedia.org/wiki/List_of_tz_database_time_zones
TIMEZONE="America/Los_Angeles"
if [ "$ARG_TAG" != "" ]; then
  IMAGE_VERSION="$ARG_TAG"
else
  ## see https://stackoverflow.com/questions/34051747/get-environment-variable-from-podman-container
  EXTRACTED_VERSION=$(podman inspect -f '{{range $index, $value := .Config.Env}}{{println $value}} {{end}}' ${IMAGE}:${IMAGE_VERSION} 2>/dev/null | grep IMAGE_VERSION)
  EXTRACTED_VERSION="${EXTRACTED_VERSION#*=}"
  ## only use extracted version if that tag exists locally
  if [ "${EXTRACTED_VERSION}" != "" ] && [ "$(podman images -q ${IMAGE}:${EXTRACTED_VERSION} 2>/dev/null)" != "" ]; then
    IMAGE_VERSION="${EXTRACTED_VERSION}"
  fi
fi
POSTGRES_VERSION=16

## what os is being used
ostype=`uname`
if [ "$ostype" == "Darwin" ]; then
  EXT="command"
else
  EXT="sh"
fi

BOUNDARY="---------------------------------------------------------------------------"

if [ "$ARG_SHOW" != "show" ]; then
  clear
fi
has_podman=$(which podman)
if [ "${has_podman}" == "" ]; then
  echo $BOUNDARY
  echo "Podman is not installed. Download and install Podman from"
  if [[ "$ostype" == "Linux" ]]; then
    echo "https://podman.io/docs/installation#linux-distributions"
  elif [[ "$ostype" == "Darwin" ]]; then
    echo "https://podman.io/docs/installation#macos"
    echo "brew install podman && podman machine init && podman machine start"
  else
    echo "https://podman.io/docs/installation#windows"
  fi
  echo $BOUNDARY
  read
else

  ## check podman machine is running (macOS/Windows)
  {
    podman ps -q 2>/dev/null
  } || {
    if [[ "$ostype" == "Darwin" ]]; then
      echo "Starting Podman machine..."
      podman machine start 2>/dev/null || podman machine init && podman machine start
      while (! podman ps -q 2>/dev/null); do
        echo "Please wait while Podman starts up ..."
        sleep 2
      done
    else
      echo $BOUNDARY
      echo "Podman is not running. Please start podman on your computer"
      echo "When podman has finished starting up press [ENTER] to continue"
      echo $BOUNDARY
      read
    fi
  }

  ## kill running containers
  running=$(podman ps -a --format {{.Names}} | grep ${LABEL} -w)
  if [ "${running}" != "" ]; then
    echo $BOUNDARY
    echo "Stopping running containers"
    echo $BOUNDARY
    podman stop ${LABEL}
    podman container rm ${LABEL} 2>/dev/null
  fi

  ## download image if not available
  available=$(podman images -q ${IMAGE}:${IMAGE_VERSION})
  if [ "${available}" == "" ]; then
    echo $BOUNDARY
    echo "Downloading the ${LABEL}:${IMAGE_VERSION} computing environment"
    echo $BOUNDARY
    podman logout 2>/dev/null
    podman pull ${IMAGE}:${IMAGE_VERSION}
  fi

  chip=""
  if [[ "$ostype" == "Linux" ]]; then
    ostype="Linux"
    if [[ "$archtype" == "aarch64" ]]; then
      chip="(ARM64)"
    else
      chip="(Intel)"
    fi
    HOMEDIR=~
    ID=$USER
    open_browser () {
      xdg-open $1
    }
    sed_fun () {
      sed -i $1 "$2"
    }
    if [ -d "/media" ]; then
      MNT="-v /media:/media"
    else
      MNT=""
    fi

    is_wsl=$(which explorer.exe)
    if [[ "$is_wsl" != "" ]]; then
      archtype=`arch`
      ostype="WSL2"
      if [[ "$archtype" == "aarch64" ]]; then
        chip="(ARM64)"
      else
        chip="(Intel)"
      fi
      HOMEDIR="/mnt/c/Users/$USER"
      if [ -d "/mnt/c" ]; then
        MNT="$MNT -v /mnt/c:/mnt/c"
      fi
      if [ -d "/mnt/d" ]; then
        MNT="$MNT -v /mnt/d:/mnt/d"
      fi
    fi
  elif [[ "$ostype" == "Darwin" ]]; then
    archtype=`arch`
    ostype="macOS"
    if [[ "$archtype" == "arm64" ]]; then
      chip="(ARM64)"
    else
      chip="(Intel)"
    fi
    HOMEDIR=~
    ID=$USER
    open_browser () {
      open $1
    }
    sed_fun () {
      sed -i '' -e $1 "$2"
    }
    MNT="-v /Volumes:/media/Volumes"
  else
    archtype=`arch`
    ostype="Windows"
    if [[ "$archtype" == "aarch64" ]]; then
      chip="(ARM64)"
    else
      chip="(Intel)"
    fi
    HOMEDIR="C:/Users/$USERNAME"
    ID=$USERNAME
    open_browser () {
      start $1
    }
    sed_fun () {
      sed -i $1 "$2"
    }
    MNT=""
  fi

  if [ "$ARG_VOLUME" != "" ]; then
    HOMEDIR="$ARG_VOLUME"
  fi

  if [ "$ARG_HOME" != "" ]; then
    ## change mapping of podman home directory to local directory if specified
    if [ "${ARG_HOME}" != "" ] && [ ! -d "${ARG_HOME}" ]; then
      echo "The directory ${ARG_HOME} does not yet exist."
      echo "Please create the directory and restart the launch script"
      sleep 5
      exit 1
    fi
    if [ "${copy_config}" == "y" ]; then
      if [ -f "${HOMEDIR}/.inputrc" ] && [ ! -s "${ARG_HOME}/.inputrc" ]; then
        MNT="$MNT -v ${HOMEDIR}/.inputrc:/home/$NB_USER/.inputrc"
      fi
      if [ -f "${HOMEDIR}/.Rprofile" ] && [ ! -s "${ARG_HOME}/.Rprofile" ]; then
        MNT="$MNT -v ${HOMEDIR}/.Rprofile:/home/$NB_USER/.Rprofile"
      fi
      if [ -f "${HOMEDIR}/.Renviron" ] && [ ! -s "${ARG_HOME}/.Renviron" ]; then
        MNT="$MNT -v ${HOMEDIR}/.Renviron:/home/$NB_USER/.Renviron"
      fi
      if [ -f "${HOMEDIR}/.gitconfig" ] && [ ! -s "${ARG_HOME}/.gitconfig" ]; then
        MNT="$MNT -v ${HOMEDIR}/.gitconfig:/home/$NB_USER/.gitconfig"
      fi
      if [ -d "${HOMEDIR}/.ssh" ]; then
        if [ ! -d "${ARG_HOME}/.ssh" ] || [ ! "$(ls -A $ARG_HOME/.ssh)" ]; then
          MNT="$MNT -v ${HOMEDIR}/.ssh:/home/$NB_USER/.ssh"
        fi
      fi
    fi

    if [ ! -f "${ARG_HOME}/.gitignore" ]; then
      ## make sure no hidden files go into a git repo
      touch "${ARG_HOME}/.gitignore"
      echo ".*" >> "${ARG_HOME}/.gitignore"
    fi

    if [ -d "${HOMEDIR}/.R" ]; then
      if [ ! -d "${ARG_HOME}/.R" ] || [ ! "$(ls -A $ARG_HOME/.R)" ]; then
        MNT="$MNT -v ${HOMEDIR}/.R:/home/$NB_USER/.R"
      fi
    fi

    if [ -d "${HOMEDIR}/Dropbox" ]; then
      if [ ! -d "${ARG_HOME}/Dropbox" ] || [ ! "$(ls -A $ARG_HOME/Dropbox)" ]; then
        MNT="$MNT -v ${HOMEDIR}/Dropbox:/home/$NB_USER/Dropbox"
        sed_fun '/^Dropbox$/d' "${ARG_HOME}/.gitignore"
        echo "Dropbox" >> "${ARG_HOME}/.gitignore"
      fi
    fi

    if [ -d "${HOMEDIR}/.rsm-msba" ] && [ ! -d "${ARG_HOME}/.rsm-msba" ]; then

      {
        which rsync 2>/dev/null
        HD="$(echo "$HOMEDIR" | sed -E "s|^([A-z]):|/\1|")"
        AH="$(echo "$ARG_HOME" | sed -E "s|^([A-z]):|/\1|")"
        rsync -a "${HD}/.rsm-msba" "${AH}/" --exclude R --exclude bin --exclude lib --exclude share
      } ||
      {
        cp -r "${HOMEDIR}/.rsm-msba" "${ARG_HOME}/.rsm-msba"
        rm -rf "${ARG_HOME}/.rsm-msba/R"
        rm -rf "${ARG_HOME}/.rsm-msba/bin"
        rm -rf "${ARG_HOME}/.rsm-msba/lib"
      }
    fi
    SCRIPT_HOME="$(script_home)"
    if [ "${SCRIPT_HOME}" != "${ARG_HOME}" ]; then
      cp -p "$0" "${ARG_HOME}/launch-${LABEL}.${EXT}"
      sed_fun "s+^ARG_HOME\=\".*\"+ARG_HOME\=\"\$\(script_home\)\"+" "${ARG_HOME}/launch-${LABEL}.${EXT}"
      if [ "$ARG_TAG" != "" ]; then
        sed_fun "s/^IMAGE_VERSION=\".*\"/IMAGE_VERSION=\"${IMAGE_VERSION}\"/" "${ARG_HOME}/launch-${LABEL}.${EXT}"
      fi
    fi
    HOMEDIR="${ARG_HOME}"
  fi

  ## adding an dir for zsh to use
  if [ ! -d "${HOMEDIR}/.rsm-msba/zsh" ]; then
    mkdir -p "${HOMEDIR}/.rsm-msba/zsh"
  fi

  BUILD_DATE=$(podman inspect -f '{{.Created}}' ${IMAGE}:${IMAGE_VERSION})

  {
    # check if network already exists
    podman network inspect ${NETWORK} >/dev/null 2>&1
  } || {
    # if network doesn't exist create it
    echo "--- Creating network: ${NETWORK} ---"
    podman network create ${NETWORK}
  }

  echo $BOUNDARY
  echo "Starting the ${LABEL} computing environment on ${ostype} ${chip}"
  echo "Version   : ${IMAGE_VERSION}"
  echo "Build date: ${BUILD_DATE//T*/}"
  echo "Base dir. : ${HOMEDIR}"
  echo $BOUNDARY

  has_volume=$(podman volume ls | awk "/pg_data/" | awk '{print $2}')
  if [ "${has_volume}" == "" ]; then
    podman volume create --name=pg_data
  fi
  {
    ## Rootless podman with --userns=keep-id maps host user to container user
    podman run --name ${LABEL} --hostname ${HOSTNAME} --net ${NETWORK} -d \
      --userns=keep-id \
      -p 127.0.0.1:2222:2222 \
      -p 127.0.0.1:8282:8282 \
      -p 127.0.0.1:8765:8765 \
      -e TZ=${TIMEZONE} \
      -v "${HOMEDIR}":/home/${NB_USER} $MNT \
      -v pg_data:/var/lib/postgresql/${POSTGRES_VERSION}/main \
      ${IMAGE}:${IMAGE_VERSION}
  } || {
    echo $BOUNDARY
    echo "It seems there was a problem starting the podman container. Please"
    echo "report the issue and add a screenshot of any messages shown on screen."
    echo "Press [ENTER] to continue"
    echo $BOUNDARY
    read
  }
  show_service () {
    echo $BOUNDARY
    echo "Starting the ${LABEL} computing environment on ${ostype} ${chip}"
    echo "Version   : ${IMAGE_VERSION}"
    echo "Build date: ${BUILD_DATE//T*/}"
    echo "Base dir. : ${HOMEDIR}"
    echo "Cont. name: ${LABEL}"
    echo $BOUNDARY
    echo "Press (1) to show a (ZSH) terminal, followed by [ENTER]:"
    echo "Press (2) to update the ${LABEL} container, followed by [ENTER]:"
    echo "Press (3) to update the launch script, followed by [ENTER]:"
    echo "Press (4) to setup Git and GitHub, followed by [ENTER]:"
    echo "Press (h) to show help in the terminal and browser, followed by [ENTER]:"
    echo "Press (c) to commit changes, followed by [ENTER]:"
    echo "Press (q) to stop the podman process, followed by [ENTER]:"
    echo $BOUNDARY
    echo "Note: To start a specific container version type, e.g., 2 ${IMAGE_VERSION} [ENTER]"
    echo "Note: To commit changes to the container type, e.g., c myversion [ENTER]"
    echo $BOUNDARY
    read menu_exec menu_arg

    # function to shut down running rsm containers
    clean_rsm_containers () {
      rsm_containers=$(podman ps -a --format {{.Names}} | grep "${LABEL}" | tr '\n' ' ')
      eval "podman stop $rsm_containers"
      eval "podman container rm $rsm_containers"
      podman network rm ${NETWORK}
    }

    if [ -z "${menu_exec}" ]; then
      echo "Invalid entry. Resetting launch menu ..."
    elif [ ${menu_exec} == 1 ]; then
      if [ "$ARG_SHOW" != "show" ]; then
        clear
      fi
      if [ "${menu_arg}" == "" ]; then
        zsh_lab="${LABEL}"
      else
        zsh_lab="${LABEL}-${menu_arg}"
      fi

      echo $BOUNDARY
      echo "ZSH terminal for container ${zsh_lab} of ${IMAGE}:${IMAGE_VERSION}"
      echo "Type 'exit' to return to the launch menu"
      echo $BOUNDARY
      echo ""
      ## git bash has issues with tty
      if [[ "$ostype" == "Windows" ]]; then
        winpty podman exec -it --user ${NB_USER} ${zsh_lab} sh
      else
        podman exec -it --user ${NB_USER} ${zsh_lab} /bin/zsh
      fi
   elif [ ${menu_exec} == 2 ]; then
      echo $BOUNDARY
      echo "Updating the ${LABEL} computing environment"
      clean_rsm_containers

      if [ "${menu_arg}" == "" ]; then
        echo "Pulling down tag \"latest\""
        VERSION=${IMAGE_VERSION}
      else
        echo "Pulling down tag ${menu_arg}"
        VERSION=${menu_arg}
      fi
      podman pull ${IMAGE}:${VERSION}
      echo $BOUNDARY
      CMD="$0"
      if [ "${menu_arg}" != "" ]; then
        CMD="$CMD -t ${menu_arg}"
      fi
      if [ "$ARG_VOLUME" != "" ]; then
        CMD="$CMD -v ${ARG_VOLUME}"
      fi
      $CMD
      exit 1
    elif [ ${menu_exec} == 3 ]; then
      echo "Updating ${IMAGE} launch script"
      clean_rsm_containers
      if [ -d "${HOMEDIR}/Desktop" ]; then
        SCRIPT_DOWNLOAD="${HOMEDIR}/Desktop"
      else
        SCRIPT_DOWNLOAD="${HOMEDIR}"
      fi
      {
        current_dir=$(pwd)
        cd ~/git/rsm-podman 2>/dev/null;
        git pull 2>/dev/null;
        cd $current_dir
        chmod 755 ~/git/rsm-podman/launch-${LABEL}.sh 2>/dev/null;
        rm -f "${LOCK_FILE}"
        eval "~/git/rsm-podman/launch-${LABEL}.sh ${LAUNCH_ARGS}"
        exit 1
        sleep 10
      } || {
        echo "Updating the launch script failed\n"
        echo "Copy the code below and run it after stopping the podman container with q + Enter\n"
        echo "rm -rf ~/git/rsm-podman;\n"
        echo "git clone https://github.com/radiant-ai-hub/rsm-podman.git ~/git/rsm-podman;\n"
        echo "\nPress any key to continue"
        read
      }
    elif [ ${menu_exec} == 4 ]; then
      echo $BOUNDARY
      echo "Setup Git and Github (y/n)?"
      echo $BOUNDARY
      read github

      if [ "${github}" == "y" ]; then
        if [ "${menu_arg}" == "" ]; then
          zsh_lab="${LABEL}"
        else
          zsh_lab="${LABEL}-${menu_arg}"
        fi

        # open_browser "https://github.com/settings/ssh/new"
        if [[ "$ostype" == "Windows" ]]; then
          winpty podman exec -it --user ${NB_USER} ${zsh_lab} /usr/local/bin/github
        else
          podman exec -it --user ${NB_USER} ${zsh_lab} /usr/local/bin/github
        fi
      fi
    elif [ "${menu_exec}" == 6 ]; then
      if [ "${menu_arg}" != "" ]; then
        selenium_port=${menu_arg}
      else
        selenium_port=4444
      fi
      CPORT=$(curl -s localhost:${selenium_port} 2>/dev/null)
      echo $BOUNDARY
      selenium_nr=($(podman ps -a | awk "/rsm-selenium/" | awk '{print $1}'))
      selenium_nr=${#selenium_nr[@]}
      if [ "$CPORT" != "" ]; then
        echo "A Selenium container may already be running on port ${selenium_port}"
        selenium_nr=$((${selenium_nr}-1))
      else
        podman run --name="rsm-selenium${selenium_nr}" --net ${NETWORK} -d -p 127.0.0.1:${selenium_port}:4444 --platform linux/arm64 seleniarm/standalone-firefox
      fi
      echo "You can access selenium at ip: rsm-selenium${selenium_nr}, port: 4444 from the"
      echo "${LABEL} container (rsm-selenium${selenium_nr}:4444) and ip: 127.0.0.1,"
      echo "port: ${selenium_port} (http://127.0.0.1:${selenium_port}) from the host OS"
      echo "Press any key to continue"
      echo $BOUNDARY
      read
    elif [ "${menu_exec}" == 7 ]; then
      if [ "${menu_arg}" != "" ]; then
        crawl_port=${menu_arg}
      else
        crawl_port=11235
      fi
      CPORT=$(curl -s localhost:${crawl_port} 2>/dev/null)
      echo $BOUNDARY
      crawl_nr=($(podman ps -a | awk "/rsm-crawl/" | awk '{print $1}'))
      crawl_nr=${#crawl_nr[@]}
      if [ "$CPORT" != "" ]; then
        echo "A Crawl4AI container may already be running on port ${crawl_port}"
        crawl_nr=$((${crawl_nr}-1))
      else
        podman run --name="rsm-crawl${crawl_nr}" --hostname ${HOSTNAME} --net ${NETWORK} -d -p 127.0.0.1:${crawl_port}:11235 --platform linux/arm64 unclecode/crawl4ai:latest
      fi
      echo "You can access crawl4ai at ip: rsm-crawl${crawl_nr}, port: 11235 from the"
      echo "${LABEL} container (rsm-crawl${crawl_nr}:11235) and ip: 127.0.0.1,"
      echo "port: ${crawl_port} (http://127.0.0.1:${crawl_port}) from the host OS"
      echo "Press any key to continue"
      echo $BOUNDARY
      read
    elif [ "${menu_exec}" == 8 ]; then
      if [ "${menu_arg}" != "" ]; then
        playr_port=${menu_arg}
      else
        playr_port=11000
      fi
      CPORT=$(curl -s localhost:${playr_port} 2>/dev/null)
      echo $BOUNDARY
      crawl_nr=($(podman ps -a | awk "/rsm-playwright/" | awk '{print $1}'))
      crawl_nr=${#crawl_nr[@]}
      if [ "$CPORT" != "" ]; then
        echo "A Playwright container may already be running on port ${playr_port}"
        playr_nr=$((${playr_nr}-1))
      else
        podman run --name="rsm-playwright${playr_nr}" --hostname ${HOSTNAME} --net ${NETWORK} -d -p 127.0.0.1:${playr_port}:3000 --platform linux/arm64 mcr.microsoft.com/playwright:latest
      fi
      echo "You can access playwright at ip: rsm-playwright${playr_nr}, port: 3000 from the"
      echo "${LABEL} container (rsm-playwright${playr_nr}:3000) and ip: 127.0.0.1,"
      echo "port: ${playr_port} (http://127.0.0.1:${playr_port}) from the host OS"
      echo "Press any key to continue"
      echo $BOUNDARY
      read
    elif [ "${menu_exec}" == "h" ]; then
      echo $BOUNDARY
      echo "Showing help for your OS in the default browser"
      echo "Showing help to start the podman container from the command line"
      echo ""
      if [[ "$ostype" == "macOS" ]]; then
        if [[ "$archtype" == "arm64" ]]; then
          open_browser https://github.com/radiant-ai-hub/rsm-podman/blob/main/install/rsm-msba-macos-arm.md
        else
          open_browser https://github.com/radiant-ai-hub/rsm-podman/blob/main/install/rsm-msba-macos.md
        fi
      elif [[ "$ostype" == "WSL2" ]]; then
        if [[ "$archtype" == "aarch64" ]]; then
          open_browser https://github.com/radiant-ai-hub/rsm-podman/blob/main/install/rsm-msba-windows-arm.md
        else
          open_browser https://github.com/radiant-ai-hub/rsm-podman/blob/main/install/rsm-msba-windows.md
        fi
      elif [[ "$ostype" == "ChromeOS" ]]; then
        open_browser https://github.com/radiant-ai-hub/rsm-podman/blob/main/install/rsm-msba-chromeos.md
      else
        open_browser https://github.com/radiant-ai-hub/rsm-podman/blob/main/install/rsm-msba-linux.md
      fi
      launch_usage noexit
      echo "Press any key to continue"
      echo $BOUNDARY
      read
    elif [ "${menu_exec}" == "c" ]; then
      container_id=($(podman ps -a | awk "/${ID}\/${LABEL}/" | awk '{print $1}'))
      if [ "${menu_arg}" == "" ]; then
        echo $BOUNDARY
        echo "Are you sure you want to over-write the current image (y/n)?"
        echo $BOUNDARY
        read menu_commit
        if [ "${menu_commit}" == "y" ]; then
          echo $BOUNDARY
          echo "Committing changes to ${IMAGE}"
          echo $BOUNDARY
          podman commit ${container_id[0]} ${IMAGE}:${IMAGE_VERSION}
        else
          return 1
        fi
        IMAGE_DHUB=${IMAGE}
      else
        menu_arg="${LABEL}-$(echo -e "${menu_arg}" | tr -d '[:space:]')"
        podman commit ${container_id[0]} $ID/${menu_arg}:${IMAGE_VERSION}

        if [ -d "${HOMEDIR}/Desktop" ]; then
          SCRIPT_COPY="${HOMEDIR}/Desktop"
        else
          SCRIPT_COPY="${HOMEDIR}"
        fi
        cp -p "$0" "${SCRIPT_COPY}/launch-${menu_arg}.${EXT}"
        sed_fun "s+^ID\=\".*\"+ID\=\"${ID}\"+" "${SCRIPT_COPY}/launch-${menu_arg}.${EXT}"
        sed_fun "s+^LABEL\=\".*\"+LABEL\=\"${menu_arg}\"+" "${SCRIPT_COPY}/launch-${menu_arg}.${EXT}"

        echo $BOUNDARY
        echo "Committing changes to ${ID}/${menu_arg}"
        echo "Use the following script to launch:"
        echo "${SCRIPT_COPY}/launch-${menu_arg}.${EXT}"
        echo $BOUNDARY
        IMAGE_DHUB=${ID}/${menu_arg}
      fi

      echo $BOUNDARY
      echo "Do you want to push this image to GHCR (y/n)?"
      echo "Note: This requires a GitHub account and GH_TOKEN in ~/.env"
      echo "Note: To specify a version tag type, e.g., y 1.3.0"
      echo $BOUNDARY
      read menu_push menu_tag
      if [ "${menu_push}" == "y" ]; then
        {
          podman login
          if [ "${menu_tag}" == "" ]; then
            podman push ${IMAGE_DHUB}:latest
          else
            if [ "${menu_arg}" == "" ]; then
              sed_fun "s/^IMAGE_VERSION=\".*\"/IMAGE_VERSION=\"${menu_tag}\"/" "$0"
            else
              sed_fun "s/^IMAGE_VERSION=\".*\"/IMAGE_VERSION=\"${menu_tag}\"/" "${SCRIPT_COPY}/launch-${menu_arg}.${EXT}"
            fi
            # echo 'podman commit --change "ENV IMAGE_VERSION=${menu_tag}" ${container_id[0]} ${IMAGE_DHUB}:${menu_tag}'
            podman commit --change "ENV IMAGE_VERSION=${menu_tag}" ${container_id[0]} ${IMAGE_DHUB}:${menu_tag}
            podman push ${IMAGE_DHUB}:${menu_tag}
          fi
        } || {
          echo $BOUNDARY
          echo "It seems there was a problem with login or pushing to image repository"
          echo $BOUNDARY
          sleep 3s
        }
      fi
    elif [ "${menu_exec}" == "q" ]; then
      echo $BOUNDARY
      echo "Stopping the ${LABEL} computing environment and cleaning up as needed"
      echo $BOUNDARY

      selenium_containers=$(podman ps -a --format {{.Names}} | grep 'selenium' | tr '\n' ' ')
      if [ "${selenium_containers}" != "" ]; then
        echo "Stopping Selenium containers ..."
        eval "podman stop $selenium_containers"
        eval "podman container rm $selenium_containers"
      fi

      crawl_containers=$(podman ps -a --format {{.Names}} | grep 'crawl' | tr '\n' ' ')
      if [ "${crawl_containers}" != "" ]; then
        echo "Stopping crawl4ai containers ..."
        eval "podman stop $crawl_containers"
        eval "podman container rm $crawl_containers"
      fi

      clean_rsm_containers

      imgs=$(podman images | awk '/<none>/ { print $3 }')
      if [ "${imgs}" != "" ]; then
        echo "Removing unused containers ..."
        podman rmi -f ${imgs}
      fi
    else
      echo "Invalid entry. Resetting launch menu ..."
    fi

    if [ "${menu_exec}" == "q" ]; then
      ## removing empty files and directories created after -v mounting
      if [ "$ARG_HOME" != "" ]; then
        echo "Removing empty files and directories ..."
        find "$ARG_HOME" -empty -type d -delete
        find "$ARG_HOME" -empty -type f -delete
      fi
      return 2
    else
      return 1
    fi
  }

  ## sleep to give the server time to start up fully
  sleep 2
  show_service
  ret=$?
  ## keep asking until quit
  while [ $ret -ne 2 ]; do
    sleep 2
    if [ "$ARG_SHOW" != "show" ]; then
      clear
    fi
    show_service
    ret=$?
  done
fi
