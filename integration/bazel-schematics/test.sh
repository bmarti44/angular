#!/usr/bin/env bash

set -eux -o pipefail

# sedi makes `sed -i` work on both OSX & Linux
# See https://stackoverflow.com/questions/2320564/i-need-my-sed-i-command-for-in-place-editing-to-work-with-both-gnu-sed-and-bsd
function sedi () {
  case $(uname) in
    Darwin*) sedi=('-i' '') ;;
    *) sedi='-i' ;;
  esac

  sed "${sedi[@]}" "$@"
}

function installLocalPackages() {
  # Install Angular packages that are built locally from HEAD.
  # This also gets around the bug whereby yarn caches local `file://` urls.
  # See https://github.com/yarnpkg/yarn/issues/2165
  readonly pwd=$(pwd)
  readonly packages=(
    animations common compiler core forms platform-browser
    platform-browser-dynamic router bazel compiler-cli language-service
  )
  local local_packages=()
  for package in "${packages[@]}"; do
    local_packages+=("@angular/${package}@file:${pwd}/../node_modules/@angular/${package}")
  done

  # keep protractor, typescript, tslib, and @types/node versions in sync with the ones used in this repo
  local_packages+=("protractor@file:${pwd}/../node_modules/protractor")
  local_packages+=("typescript@file:${pwd}/../node_modules/typescript")
  local_packages+=("tslib@file:${pwd}/../node_modules/tslib")
  local_packages+=("@types/node@file:${pwd}/../node_modules/@types/node")

  # add protractor, puppeteer & webdriver-manager so we get the chrome & chromedriver binaries
  # that have already been downloaded at the root
  local_packages+=("puppeteer@file:${pwd}/../node_modules/puppeteer")
  local_packages+=("webdriver-manager@file:${pwd}/../node_modules/webdriver-manager")

  yarn add --ignore-scripts --silent "${local_packages[@]}"
}

function patchKarmaConf() {
  sedi "s#module.exports#process.env.CHROME_BIN = require\('puppeteer'\).executablePath\(\); module.exports#" ./karma.conf.js
  sedi "s#browsers\: \['Chrome'\],#customLaunchers\: \{ ChromeHeadlessNoSandbox\: \{ base\: 'ChromeHeadless', flags\: \['--no-sandbox', '--headless', '--disable-gpu', '--disable-dev-shm-usage', '--hide-scrollbars', '--mute-audio'\] \} \}, browsers\: \['ChromeHeadlessNoSandbox'\],#" ./karma.conf.js
}

function patchProtractorConf() {
  sedi "s#browserName\: 'chrome'#browserName\: 'chrome', chromeOptions\: \{ binary: require\('puppeteer'\).executablePath\(\), args: \['--no-sandbox', '--headless', '--disable-gpu', '--disable-dev-shm-usage', '--hide-scrollbars', '--mute-audio'\] \},#" ./e2e/protractor.conf.js
}

function testBazel() {
  # Set up
  bazel version
  ng version
  rm -rf demo
  # Create project
  ng new demo --collection=@angular/bazel --routing --skip-git --skip-install --style=scss
  cd demo
  patchKarmaConf
  patchProtractorConf
  installLocalPackages
  ng generate component widget --style=css
  ng build
  ng test
  ng e2e
  ng e2e --prod
  if [ -e 'WORKSPACE' ] || [ -e 'BUILD.bazel' ]; then
    echo 'WORKSPACE / BUILD.bazel file should not exist in project'
    exit 1
  fi
}

function testNonBazel() {
  # Replace angular.json that uses Bazel builder with the default generated by CLI
  mv ./angular.json.bak ./angular.json
  rm -rf dist src/main.dev.ts src/main.prod.ts
  # disable CLI's version check (if version is 0.0.0, then no version check happens)
  yarn --cwd node_modules/@angular/cli version --new-version 0.0.0 --no-git-tag-version
  # re-add build-angular
  yarn add --dev file:../node_modules/@angular-devkit/build-angular
  ng build --progress=false
  ng test --progress=false --watch=false
  ng e2e --port 0 --configuration=production --webdriver-update=false
}

testBazel

# this test verifies that users can undo bazel - the value of this is questionable
# because there are way too many manual steps and it would be easier for users to
# just revert the diff created by `ng add @angular/bazel`
testNonBazel
