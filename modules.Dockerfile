FROM alpine:latest

RUN apk --update add build-base python3 python3-dev py3-pip git zlib-dev jpeg-dev

RUN git clone https://github.com/MISP/misp-modules.git /modules
WORKDIR /modules
RUN pip3 install -r REQUIREMENTS
RUN pip3 install click
RUN python3 setup.py install

EXPOSE 6666
CMD /bin/sh -c "misp-modules -s -l 0.0.0.0"
