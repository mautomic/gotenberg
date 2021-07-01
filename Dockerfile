# Unified dockerfile for creating a custom image with modified gotenberg source code

ARG GOTENBERG_VERSION=1.0
ARG GOLANG_VERSION=1.16.0

FROM golang:${GOLANG_VERSION}-stretch AS golang

FROM debian:buster-slim

# |--------------------------------------------------------------------------
# | Common libraries
# |--------------------------------------------------------------------------
RUN apt-get update &&\
    apt-get --no-install-recommends install -y ca-certificates curl gnupg procps &&\
    rm -rf /var/lib/apt/lists/*

# |--------------------------------------------------------------------------
# | Microsoft font installer
# |--------------------------------------------------------------------------
RUN apt-get update &&\
    curl -o ./ttf-mscorefonts-installer_3.8_all.deb http://httpredir.debian.org/debian/pool/contrib/m/msttcorefonts/ttf-mscorefonts-installer_3.8_all.deb &&\
    apt --no-install-recommends install -y ./ttf-mscorefonts-installer_3.8_all.deb && rm ./ttf-mscorefonts-installer_3.8_all.deb &&\
    rm -rf /var/lib/apt/lists/*

# |--------------------------------------------------------------------------
# | Chrome
# |--------------------------------------------------------------------------
RUN curl https://dl.google.com/linux/linux_signing_key.pub | apt-key add - &&\
    echo "deb http://dl.google.com/linux/chrome/deb/ stable main" | tee /etc/apt/sources.list.d/google-chrome.list &&\
    apt-get update &&\
    apt-get install --no-install-recommends -y --allow-unauthenticated google-chrome-stable &&\
    rm -rf /var/lib/apt/lists/*

# |--------------------------------------------------------------------------
# | LibreOffice
# |--------------------------------------------------------------------------
# https://github.com/nextcloud/docker/issues/380
RUN mkdir -p /usr/share/man/man1mkdir -p /usr/share/man/man1 &&\
    echo "deb http://httpredir.debian.org/debian/ buster-backports main contrib non-free" >> /etc/apt/sources.list &&\
    apt-get update &&\
    apt-get --no-install-recommends -t buster-backports -y install libreoffice &&\
    rm -rf /var/lib/apt/lists/*

# |--------------------------------------------------------------------------
# | Unoconv
# |--------------------------------------------------------------------------
ENV UNO_URL=https://raw.githubusercontent.com/dagwieers/unoconv/master/unoconv

RUN curl -Ls $UNO_URL -o /usr/bin/unoconv &&\
    chmod +x /usr/bin/unoconv &&\
    ln -s /usr/bin/python3 /usr/bin/python &&\
    unoconv --version

# |--------------------------------------------------------------------------
# | PDFtk
# |--------------------------------------------------------------------------
# | https://github.com/thecodingmachine/gotenberg/issues/29
ARG PDFTK_VERSION=924565150

RUN curl -o /usr/bin/pdftk "https://gitlab.com/pdftk-java/pdftk/-/jobs/${PDFTK_VERSION}/artifacts/raw/build/native-image/pdftk" \
    && chmod a+x /usr/bin/pdftk

# |--------------------------------------------------------------------------
# | Fonts
# |--------------------------------------------------------------------------
# Credits:
# https://github.com/arachnys/athenapdf/blob/master/cli/Dockerfile
# https://help.accusoft.com/PrizmDoc/v12.1/HTML/Installing_Asian_Fonts_on_Ubuntu_and_Debian.html
RUN apt-get update &&\
    apt-get install --no-install-recommends -y \
    culmus \
    fonts-beng \
    fonts-hosny-amiri \
    fonts-lklug-sinhala \
    fonts-lohit-guru \
    fonts-lohit-knda \
    fonts-samyak-gujr \
    fonts-samyak-mlym \
    fonts-samyak-taml \
    fonts-sarai \
    fonts-sil-abyssinica \
    fonts-sil-padauk \
    fonts-telu \
    fonts-thai-tlwg \
    ttf-wqy-zenhei \
    fonts-arphic-uming \
    fonts-ipafont-mincho \
    fonts-ipafont-gothic \
    fonts-unfonts-core \
    # LibreOffice recommends.
    fonts-crosextra-caladea \
    fonts-crosextra-carlito \
    fonts-dejavu \
    fonts-dejavu-extra \
    fonts-liberation \
    fonts-liberation2 \
    fonts-linuxlibertine \
    fonts-noto-core \
    fonts-noto-mono \
    fonts-noto-ui-core \
    fonts-sil-gentium \
    fonts-sil-gentium-basic &&\
    rm -rf /var/lib/apt/lists/*

COPY build/base/fonts/* /usr/local/share/fonts/
COPY build/base/fonts.conf /etc/fonts/conf.d/100-gotenberg.conf

# |--------------------------------------------------------------------------
# | Default user
# |--------------------------------------------------------------------------
# | All processes in the Docker container will run as a dedicated
# | non-root user.
ARG GOTENBERG_USER_ID=1001

RUN groupadd --gid ${GOTENBERG_USER_ID} gotenberg \
  && useradd --uid ${GOTENBERG_USER_ID} --gid gotenberg --shell /bin/bash --home /gotenberg --no-create-home gotenberg \
  && mkdir /gotenberg \
  && chown gotenberg: /gotenberg

# |--------------------------------------------------------------------------
# | Common libraries
# |--------------------------------------------------------------------------
# | Libraries used in the build process of this image.
RUN apt-get update && apt-get install -y --no-install-recommends \
        git \
		g++ \
		gcc \
		libc6-dev \
		make \
		pkg-config \
	&& rm -rf /var/lib/apt/lists/*

# |--------------------------------------------------------------------------
# | Golang
# |--------------------------------------------------------------------------
# | Installs Golang.
COPY --from=golang /usr/local/go /usr/local/go

ENV GOPATH /gotenberg/go
ENV PATH $GOPATH/bin:/usr/local/go/bin:$PATH

RUN mkdir -p "$GOPATH/src" "$GOPATH/bin" &&\
    chmod -R 777 "$GOPATH"

# |--------------------------------------------------------------------------
# | Final touch
# |--------------------------------------------------------------------------
# | Last instructions of this build.

# Make sure the Gotenber user is able to
# call the Go binary.
USER gotenberg

RUN go version &&\
    go env

USER root

# |--------------------------------------------------------------------------
# | Binary
# |--------------------------------------------------------------------------
ENV GOOS=linux \
    GOARCH=amd64 \
    CGO_ENABLED=0

# Define our workding outside of $GOPATH (we're using go modules).
WORKDIR /gotenberg/package

# Install module dependencies.
COPY go.mod go.sum ./

RUN go mod download &&\
    go mod verify

# Copy our source code.
COPY internal ./internal
COPY cmd ./cmd

# Build our binary.
RUN go build -o gotenberg -ldflags "-X main.version=${GOTENBERG_VERSION}" cmd/gotenberg/main.go

# |--------------------------------------------------------------------------
# | Tini
# |--------------------------------------------------------------------------
# | An helper for reaping zombie processes.
ARG TINI_VERSION=0.19.0

ADD https://github.com/krallin/tini/releases/download/v${TINI_VERSION}/tini-static /tini
RUN chmod +x /tini
ENTRYPOINT [ "/tini", "--" ]

USER gotenberg
WORKDIR /gotenberg

EXPOSE 3000
CMD [ "package/gotenberg" ]
