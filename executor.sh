declare -a os=('u12' 'u14')
declare -a languages=('php')
declare -a languageVersions=('' 'pls' 'all')

imageTag="prod"
level="base"
should_push=true
current_file_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SUCCESSFULLY_PATCHED_IMAGES=()
TEST_FAILED_IMAGES=()
PUSH_FAILED_IMAGES=()

build_image() {
  osVer=$1
  lang=$2
  langVer=$3

  if [ "$langVer" == "pls" ]; then
    level="pls"
  fi

  if [ "$langVer" == "all" ]; then
    level="all"
  fi

  if [ -f "$current_file_dir/patch.sh" ]; then
    rm $current_file_dir/patch.sh
  fi

  touch $current_file_dir/patch.sh
  chmod +x $current_file_dir/patch.sh

  #append global level patch
  create_patch_file "$current_file_dir/global"
  #append os specific patch
  create_patch_file "$current_file_dir/os/$osVer"
  #append language specific patch
  create_patch_file "$current_file_dir/languages/$lang"

  #append image specific patch
  if [ -d "$current_file_dir/language/$lang" ]; then
    if [ -f "$current_file_dir/language/$lang/$osVer$lang$langVer-patch.sh" ]; then
      cat $current_file_dir/language/$lang/$osVer$lang$langVer-patch.sh >> patch.sh
    fi
  fi

  create_patch_test_dir "$osVer" "$lang" "$langVer"

  create_docker_file "$osVer" "$lang" "$langVer"

  docker build -t="drydock/$osVer$lang$langVer:$imageTag" $current_file_dir
}

create_patch_file() {
  path=$1
  if [ -d "$path" ]; then
    if [ -f "$path/base-patch.sh" ]; then
      cat $path/base-patch.sh >> patch.sh
    fi

    if [ "$level" == "pls" ] || [ "$level" == "all" ]; then
      if [ -f "$path/pls-patch.sh" ]; then
        cat $path/pls-patch.sh >> patch.sh
      fi
    fi

    if [ "$level" == "all" ]; then
      if [ -f "$path/all-patch.sh" ]; then
        cat $path/all-patch.sh >> patch.sh
      fi
    fi
  fi
}

create_patch_test_dir() {
  osVer=$1
  lang=$2
  langVer=$3

  if [ -d "$current_file_dir/patch_test" ]; then
    rm -r $current_file_dir/patch_test
  fi

  if [ "$lang" != "" ] || [ "$langVer" != "" ]; then
    mkdir $current_file_dir/patch_test
    if [ "$lang" != "" ]; then
      cp $current_file_dir'/tests/languages/'$lang'.sh' $current_file_dir/'patch_test'
      cp $current_file_dir'/tests/languages/executor.sh' $current_file_dir/'patch_test'
    fi
    # Run only pls and all tests if language is not present and services exist
    if [ "$langVer" != "" ] && [ "$lang" == "" ]; then
      cp $current_file_dir/'tests/'$langVer/* $current_file_dir/'patch_test'
    fi
  fi
}

create_docker_file() {
  osVer=$1
  lang=$2
  langVer=$3

  if [ -f "$current_file_dir/Dockerfile" ]; then
    rm $current_file_dir/Dockerfile
  fi

  touch $current_file_dir/Dockerfile

  echo "FROM drydock/$osVer$lang$langVer:marker" >> Dockerfile
  echo "ADD ./patch.sh /$osVer$lang$langVer/patch.sh" >> Dockerfile
  echo "ADD ./patch_test /$osVer$lang$langVer/patch_test" >> Dockerfile
  echo "RUN ./$osVer$lang$langVer/patch.sh" >> Dockerfile
}

test_image() {

  if [ "$lang" != "" ] || [ "$langVer" != "" ]; then
    echo 'Starting tests for image -----> '$osVer$lang$langVer
    #run the commands in a daemon mode
    containerId=$(docker run -d drydock/$osVer$lang$langVer':'$imageTag /bin/bash -c "/$osVer$lang$langVer/patch_test/executor.sh")
    exitCode=$(docker wait $containerId)

    #commands failed inside container
    if [ "$exitCode" != 0 ]; then
      echo 'Tests failed for image -----> '$osVer$lang$langVer
      should_push=false
      TEST_FAILED_IMAGES+=("$osVer$lang$langVer")
      docker logs $containerId
    else
      echo 'All tests passed for image -----> '$osVer$lang$langVer
    fi
  else
    echo 'Skipping tests for image -----> '$osVer$lang$langVer
  fi
}

clear_files() {
  if [ -d "$current_file_dir/patch_test" ]; then
    rm -r $current_file_dir/patch_test
  fi

  if [ -f "$current_file_dir/patch.sh" ]; then
    rm $current_file_dir/patch.sh
  fi

  if [ -f "$current_file_dir/Dockerfile" ]; then
    rm $current_file_dir/Dockerfile
  fi

  level="base"
  should_push=true
  imageId_before_push=''
  imageId_after_push=''
}

push_image() {
  osVer=$1
  lang=$2
  langVer=$3

  imageId_before_push=`docker images | grep -w 'drydock/'$osVer$lang$langVer | grep $imageTag | awk {'print $3'}`

  docker push 'drydock/'$osVer$lang$langVer':'$imageTag

  docker pull 'drydock/'$osVer$lang$langVer':'$imageTag

  imageId_after_push=`docker images | grep -w 'drydock/'$osVer$lang$langVer | grep $imageTag | awk {'print $3'}`

  if [ "$imageId_before_push" != "$imageId_after_push" ]; then
    PUSH_FAILED_IMAGES+=("$osVer$lang$langVer")
  else
    SUCCESSFULLY_PATCHED_IMAGES+=("$osVer$lang$langVer")
  fi

}

display_results() {

  if [ ${#SUCCESSFULLY_PATCHED_IMAGES[@]} != 0 ]; then
    echo "<=============== SUCCESSFULLY PASSED IMAGES =================>"
    for passedImage in "${SUCCESSFULLY_PATCHED_IMAGES[@]}"
      do
        echo $passedImage
      done
    echo "<============================================================>"
  fi
  if [ ${#TEST_FAILED_IMAGES[@]} != 0 ]; then
    echo "<=============== IMAGES FOR WHICH TESTS FAILED ===============>"
    for testFailedImage in "${TEST_FAILED_IMAGES[@]}"
      do
        echo $testFailedImage
      done
    echo "<============================================================>"
  fi

  if [ ${#PUSH_FAILED_IMAGES[@]} != 0 ]; then
    echo "<================ IMAGES FOR WHICH PUSH FAILED ================>"
    for pushFailedImage in "${PUSH_FAILED_IMAGES[@]}"
      do
        echo $pushFailedImage
      done
    echo "<============================================================>"
  fi

  if [ ${#TEST_FAILED_IMAGES[@]} != 0 ] || [ ${#PUSH_FAILED_IMAGES[@]} != 0 ]; then
    return 99
  fi
}

for osVer in "${os[@]}"
  do
    for lang in "${languages[@]}"
      do
        for langVer in "${languageVersions[@]}"
         do
            build_image "$osVer" "$lang" "$langVer"
            test_image
            if [ "$should_push" == true ]; then
              push_image "$osVer" "$lang" "$langVer"
            fi
            clear_files
         done
      done
  done

display_results
