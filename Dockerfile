# Still a WIP

# Target base image
FROM trzeci/emscripten:sdk-tag-1.39.4-64bit as emscripten_base

# Download Node.js binaries
WORKDIR /usr/src
RUN wget -O- https://nodejs.org/dist/v13.9.0/node-v13.9.0-linux-x64.tar.xz | tar -xJf-

WORKDIR /usr/src/app

# Install Yarn 2
RUN /usr/src/node-v13.9.0-linux-x64/bin/npx yarn set version berry
RUN echo "#!/bin/sh\n/usr/src/node-v13.9.0-linux-x64/bin/node" $(awk '{ print $2 }' .yarnrc.yml) "\$*" > /usr/bin/yarn
RUN chmod +x /usr/bin/yarn

COPY . .

RUN make deps
RUN make all -j4
