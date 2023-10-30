#!/usr/bin/env bash

set -eo pipefail

echo "Starting script..."

ARCHS="arm64 amd64"

echo "Architecture set to: ${ARCHS}"

docker_tag=$1

if [[ -n "${docker_tag}" ]]; then
	echo "Docker tag is set: ${docker_tag}"
	for arch in ${ARCHS}; do
		echo "Current architecture: ${arch}"
		my_image=$(docker buildx build . --platform linux/${arch} --target image --output type=docker,dest=runtime-${arch}.tar)
		echo "Docker image built: ${my_image}, exit status: $?"
		crossplane xpkg build --package-file=${arch}.xpkg --package-root=package/ --embed-runtime-image-tarball=runtime-${arch}.tar
		echo "Crossplane package built for ${arch}, exit status: $?"
		crossplane xpkg push ${docker_tag} -f ${arch}.xpkg
		echo "Crossplane package pushed for ${arch}, exit status: $?"
	done
else
	echo "my_image variable is not set."
fi

echo "Script ended."
