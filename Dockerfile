FROM python:2.7.18-buster

WORKDIR /app

RUN git config --global url."https://".insteadOf git://

ADD ./julia /app/julia
# make julia executable
RUN chmod +x /app/julia/bin/julia
# install julia packages
RUN /app/julia/bin/julia -e 'Pkg.init()' \
&& /app/julia/bin/julia -e 'Pkg.add("JSON")' \
&& /app/julia/bin/julia -e 'Pkg.add("JuMP")' \
&& /app/julia/bin/julia -e 'Pkg.add("PyCall")' \
&& /app/julia/bin/julia -e 'Pkg.add("Logging")' \
&& /app/julia/bin/julia -e 'Pkg.add("ArgParse")' \
&& /app/julia/bin/julia -e 'Pkg.add("GLPKMathProgInterface")'
# RUN export JULIA_DEPOT_PATH="/config/.julia"
# ADD ./.julia /config/.julia


# Install dependencies
RUN pip install pyyaml \
&& pip install jinja2


ADD ./src /app/src
ADD ./examples /app/examples

# echo the python version when the container starts
# CMD ["python", "--version"]

# echo the julia version when the container starts
CMD ["/app/julia/bin/julia", "/app/src/jl/benchmark.jl", "-i", "/app/examples/test", "-o", "/app/examples/test"]
# CMD ["ls", "-l", "/app/julia/bin/julia"]