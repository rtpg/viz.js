# Still a WIP

# Target base image
FROM trzeci/emscripten:sdk-tag-1.39.4-64bit as emscripten_base

# Download Node.js binaries
WORKDIR /usr/src
RUN wget -O- https://nodejs.org/dist/v13.9.0/node-v13.9.0-linux-x64.tar.xz | tar -xJf-

WORKDIR /usr/src/app

COPY . .

RUN make deps
RUN make all -j4
