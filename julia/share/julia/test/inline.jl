# This file is a part of Julia. License is MIT: http://julialang.org/license

using Base.Test

"""
Helper to walk the AST and call a function on every node.
"""
function walk(func, expr)
    func(expr)
    if isa(expr, Expr)
        func(expr.head)
        for o in expr.args
            walk(func, o)
        end
    end
end

"""
Helper to test that every SymbolNode/NewvarNode has a
corresponding varinfo entry after inlining.
"""
function test_inlined_symbols(func, argtypes)
    linfo = code_typed(func, argtypes)[1]
    locals = linfo.args[2][1]
    local_names = Set([name for (name, typ, flag) in locals])
    ast = linfo.args[3]
    walk(ast) do e
        if isa(e, NewvarNode) || isa(e, SymbolNode)
            @test e.name in local_names
        end
    end
end

# Test case 1:
# Make sure that all symbols are properly escaped after inlining
# https://github.com/JuliaLang/julia/issues/12620
@inline function test_inner(count)
    x = 1
    i = 0
    while i <= count
        y = x
        x = x + y
        i += 1
    end
end
function test_outer(a)
    test_inner(a)
end
test_inlined_symbols(test_outer, Tuple{Int64})

# Test case 2:
# Make sure that an error is thrown for the undeclared
# y in the else branch.
# https://github.com/JuliaLang/julia/issues/12620
@inline function foo(x)
    if x
        y = 2
    else
        return y
    end
end
function bar()
    for i = 1:3
        foo(i==1)
    end
end
@test_throws UndefVarError bar()

