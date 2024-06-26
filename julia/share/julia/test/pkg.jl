# This file is a part of Julia. License is MIT: http://julialang.org/license

function temp_pkg_dir(fn::Function)
    # Used in tests below to setup and teardown a sandboxed package directory
    const tmpdir = ENV["JULIA_PKGDIR"] = joinpath(tempdir(),randstring())
    @test !isdir(Pkg.dir())
    try
        Pkg.init()
        @test isdir(Pkg.dir())
        Pkg.resolve()

        fn()
    finally
        rm(tmpdir, recursive=true)
    end
end

# Test basic operations: adding or removing a package, status, free
# Also test for the existence of REQUIRE and META_Branch
temp_pkg_dir() do
    @test isfile(joinpath(Pkg.dir(),"REQUIRE"))
    @test isfile(joinpath(Pkg.dir(),"META_BRANCH"))
    @test isempty(Pkg.installed())
    @test sprint(io -> Pkg.status(io)) == "No packages installed\n"
    @test !isempty(Pkg.available())

    # check that versioninfo(io, true) doesn't error and produces some output
    # (done here since it calls Pkg.status which might error or clone metadata)
    buf = PipeBuffer()
    versioninfo(buf, true)
    ver = readall(buf)
    @test startswith(ver, "Julia Version $VERSION")
    @test contains(ver, "Environment:")

    Pkg.add("Example")
    @test [keys(Pkg.installed())...] == ["Example"]
    iob = IOBuffer()
    Pkg.checkout("Example")
    Pkg.status("Example", iob)
    str = chomp(takebuf_string(iob))
    @test startswith(str, " - Example")
    @test endswith(str, "master")
    Pkg.free("Example")
    Pkg.status("Example", iob)
    str = chomp(takebuf_string(iob))
    @test endswith(str, string(Pkg.installed("Example")))
    Pkg.checkout("Example")
    Pkg.free(("Example",))
    Pkg.status("Example", iob)
    str = chomp(takebuf_string(iob))
    @test endswith(str, string(Pkg.installed("Example")))
    Pkg.rm("Example")
    @test isempty(Pkg.installed())
    @test !isempty(Pkg.available("Example"))
    @test_throws ErrorException Pkg.available("FakePackageDoesn'tExist")
    Pkg.clone("https://github.com/JuliaLang/Example.jl.git")
    @test [keys(Pkg.installed())...] == ["Example"]
    Pkg.status("Example", iob)
    str = chomp(takebuf_string(iob))
    @test startswith(str, " - Example")
    @test endswith(str, "master")
    Pkg.free("Example")
    Pkg.status("Example", iob)
    str = chomp(takebuf_string(iob))
    @test endswith(str, string(Pkg.installed("Example")))
    Pkg.checkout("Example")
    Pkg.free(("Example",))
    Pkg.status("Example", iob)
    str = chomp(takebuf_string(iob))
    @test endswith(str, string(Pkg.installed("Example")))
    @test isempty(Pkg.dependents("Example"))

    # adding a package with unsatisfiable julia version requirements (REPL.jl) errors
    try
        Pkg.add("REPL")
        error("unexpected")
    catch err
        @test err.exceptions[1].ex.msg == "REPL can't be installed because " *
            "it has no versions that support $VERSION of julia. You may " *
            "need to update METADATA by running `Pkg.update()`"
    end

    # trying to add, check availability, or pin a nonexistent package errors
    try
        Pkg.add("NonexistentPackage")
        error("unexpected")
    catch err
        @test err.exceptions[1].ex.msg == "unknown package NonexistentPackage"
    end
    try
        Pkg.available("NonexistentPackage")
        error("unexpected")
    catch err
        @test err.msg == "NonexistentPackage is not a package (not registered or installed)"
    end
    try
        Pkg.pin("NonexistentPackage", v"1.0.0")
        error("unexpected")
    catch err
        @test err.msg == "NonexistentPackage is not a git repo"
    end

    # trying to pin a git repo under Pkg.dir that is not an installed package errors
    try
        Pkg.pin("METADATA", v"1.0.0")
        error("unexpected")
    catch err
        @test err.msg == "METADATA cannot be pinned – not an installed package"
    end

    # trying to pin an installed, registered package to an unregistered version errors
    try
        Pkg.pin("Example", v"2147483647.0.0")
        error("unexpected")
    catch err
        @test err.msg == "Example – 2147483647.0.0 is not a registered version"
    end

    Pkg.rm("Example")
    @test isempty(Pkg.installed())
end

# testing a package with test dependencies causes them to be installed for the duration of the test
temp_pkg_dir() do
    Pkg.generate("PackageWithTestDependencies", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))
    @test [keys(Pkg.installed())...] == ["PackageWithTestDependencies"]
    @test readall(Pkg.dir("PackageWithTestDependencies","REQUIRE")) == "julia $(Pkg.Generate.versionfloor(VERSION))\n"

    isdir(Pkg.dir("PackageWithTestDependencies","test")) || mkdir(Pkg.dir("PackageWithTestDependencies","test"))
    open(Pkg.dir("PackageWithTestDependencies","test","REQUIRE"),"w") do f
        println(f,"Example")
    end

    open(Pkg.dir("PackageWithTestDependencies","test","runtests.jl"),"w") do f
        println(f,"using Base.Test")
        println(f,"@test haskey(Pkg.installed(), \"Example\")")
    end

    Pkg.resolve()
    @test [keys(Pkg.installed())...] == ["PackageWithTestDependencies"]

    Pkg.test("PackageWithTestDependencies")

    @test [keys(Pkg.installed())...] == ["PackageWithTestDependencies"]

    # trying to pin an unregistered package errors
    try
        Pkg.pin("PackageWithTestDependencies", v"1.0.0")
        error("unexpected")
    catch err
        @test err.msg == "PackageWithTestDependencies cannot be pinned – not a registered package"
    end
end

# testing a package with no runtests.jl errors
temp_pkg_dir() do
    Pkg.generate("PackageWithNoTests", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))

    if isfile(Pkg.dir("PackageWithNoTests", "test", "runtests.jl"))
        rm(Pkg.dir("PackageWithNoTests", "test", "runtests.jl"))
    end

    try
        Pkg.test("PackageWithNoTests")
        error("unexpected")
    catch err
        @test err.msg == "PackageWithNoTests did not provide a test/runtests.jl file"
    end
end

# testing a package with failing tests errors
temp_pkg_dir() do
    Pkg.generate("PackageWithFailingTests", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))

    isdir(Pkg.dir("PackageWithFailingTests","test")) || mkdir(Pkg.dir("PackageWithFailingTests","test"))
    open(Pkg.dir("PackageWithFailingTests", "test", "runtests.jl"),"w") do f
        println(f,"using Base.Test")
        println(f,"@test false")
    end

    try
        Pkg.test("PackageWithFailingTests")
        error("unexpected")
    catch err
        @test err.msg == "PackageWithFailingTests had test errors"
    end
end

# Testing with code-coverage
temp_pkg_dir() do
    Pkg.generate("PackageWithCodeCoverage", "MIT", config=Dict("user.name"=>"Julia Test", "user.email"=>"test@julialang.org"))

    src = """
module PackageWithCodeCoverage

export f1, f2, f3, untested

f1(x) = 2x
f2(x) = f1(x)
function f3(x)
    3x
end
untested(x) = 7

end"""
    linetested = [false, false, false, false, true, true, false, true, false, false]
    open(Pkg.dir("PackageWithCodeCoverage", "src", "PackageWithCodeCoverage.jl"), "w") do f
        println(f, src)
    end
    isdir(Pkg.dir("PackageWithCodeCoverage","test")) || mkdir(Pkg.dir("PackageWithCodeCoverage","test"))
    open(Pkg.dir("PackageWithCodeCoverage", "test", "runtests.jl"),"w") do f
        println(f,"using PackageWithCodeCoverage, Base.Test")
        println(f,"@test f2(2) == 4")
        println(f,"@test f3(5) == 15")
    end

    Pkg.test("PackageWithCodeCoverage")
    covdir = Pkg.dir("PackageWithCodeCoverage","src")
    covfiles = filter!(x -> contains(x, "PackageWithCodeCoverage.jl") && contains(x,".cov"), readdir(covdir))
    @test isempty(covfiles)
    Pkg.test("PackageWithCodeCoverage", coverage=true)
    covfiles = filter!(x -> contains(x, "PackageWithCodeCoverage.jl") && contains(x,".cov"), readdir(covdir))
    @test !isempty(covfiles)
    for file in covfiles
        @test isfile(joinpath(covdir,file))
        covstr = readall(joinpath(covdir,file))
        srclines = split(src, '\n')
        covlines = split(covstr, '\n')
        for i = 1:length(linetested)
            covline = (linetested[i] ? "        1 " : "        - ")*srclines[i]
            @test covlines[i] == covline
        end
    end

    # issue #15948
    let package = "Example"
        Pkg.rm(package)  # Remove package if installed
        @test Pkg.installed(package) == nothing  # Registered with METADATA but not installed
        msg = readall(ignorestatus(`$(Base.julia_cmd()) -f -e "redirect_stderr(STDOUT); Pkg.build(\"$package\")"`))
        @test contains(msg, "$package is not an installed package")
        @test !contains(msg, "signal (15)")
    end
end
