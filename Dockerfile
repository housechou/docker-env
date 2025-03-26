ARG BASE_IMAGE
FROM ${BASE_IMAGE}
MAINTAINER HouseChou

ARG workspace
ARG user
ARG uid
ARG gid=1000
ARG timezone=/usr/share/zoneinfo/UTC

ENV BUILD_WORKSPACE $workspace
ENV BUILD_USER $user
ENV BUILD_UID $uid
ENV BUILD_GID $gid
ENV BUILD_TIMEZONE $timezone
ENV DEBIAN_FRONTEND noninteractive

RUN apt-get update -y --fix-missing

# For sudo
RUN apt-get install -y sudo
RUN echo "$BUILD_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

# Put what packages you want install here
# RUN apt-get install -y build-essential gcc g++ autoconf automake libtool bison flex gettext
# RUN apt-get install -y patch subversion texinfo wget git-core
# RUN apt-get install -y libncurses5 libncurses5-dev
# RUN apt-get install -y zlib1g-dev liblzo2-2 liblzo2-dev
# RUN apt-get install -y libacl1 libacl1-dev gawk cvs curl lzma
# RUN apt-get install -y uuid-dev mercurial unzip
# RUN apt-get install -y libftdi-dev
# RUN apt-get install -y bc quilt
# RUN apt-get install -y lib32stdc++6 lib32z1 libusb-1.0-0-dev
# RUN apt-get install -y python3 python3-dev python3-serial python3-usb python3-pycryptodome python3-pyelftools
# RUN apt-get install -y cpio rsync sudo libpci-dev libfdt-dev dosfstools rar
# RUN apt-get install -y libssl-dev
# RUN apt-get install -y libyaml-dev
# RUN apt-get install -y libnl-genl-3-dev
# RUN apt-get install -y fdisk
#
# # Useful rg
# RUN curl -LO https://github.com/BurntSushi/ripgrep/releases/download/11.0.2/ripgrep_11.0.2_amd64.deb
# RUN dpkg -i ripgrep_11.0.2_amd64.deb
#
# # For enviorment
# RUN apt-get install -y vim colormake bash-completion

# Create build user
RUN echo "$BUILD_USER ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
RUN groupadd -g $BUILD_GID $BUILD_USER
RUN useradd -m -s /bin/bash -N -u $BUILD_UID -g $BUILD_GID $BUILD_USER

# Create alias
RUN echo "alias ll='ls -l'" >> /home/$BUILD_USER/.bashrc
RUN echo "alias vi='vim'" >> /home/$BUILD_USER/.bashrc

# Timezone configuration
RUN apt-get install -y tzdata
RUN ln -fs $BUILD_TIMEZONE /etc/localtime
RUN dpkg-reconfigure tzdata

WORKDIR $BUILD_WORKSPACE

CMD ["/bin/bash"]

USER $BUILD_USER
