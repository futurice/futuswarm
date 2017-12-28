FROM ubuntu:16.04
ENV DEBIAN_FRONTEND noninteractive
RUN apt-get update && apt-get install -y \
    python

ADD start.sh /
ADD index.html /
ADD index.css /

EXPOSE 8000

CMD ["bash", "start.sh"]
