
module Scale

using Color
using Compose
using DataArrays
using Gadfly

import Gadfly: element_aesthetics, isconcrete, concrete_length,
               nonzero_length, formatter, setfield!, set

include("color.jl")

# Apply some scales to data in the given order.
#
# Args:
#   scales: An iterable object of ScaleElements.
#   aess: Aesthetics (of the same length as datas) to update with scaled data.
#   datas: Zero or more data objects. (Yes, I know "datas" is not a real word.)
#
# Returns:
#   nothing
#
function apply_scales(scales,
                      aess::Vector{Gadfly.Aesthetics},
                      datas::Gadfly.Data...)
    for scale in scales
        apply_scale(scale, aess, datas...)
    end

    for (aes, data) in zip(aess, datas)
        aes.titles = data.titles
    end
end


# Apply some scales to data in the given order.
#
# Args:
#   scales: An iterable object of ScaleElements.
#   datas: Zero or more data objects.
#
# Returns:
#   A vector of Aesthetics of the same length as datas containing scaled data.
#
function apply_scales(scales, datas::Gadfly.Data...)
    aess = Gadfly.Aesthetics[Gadfly.Aesthetics() for _ in datas]
    apply_scales(scales, aess, datas...)
    aess
end


# Transformations on continuous scales
immutable ContinuousScaleTransform
    f::Function     # transform function
    finv::Function  # f's inverse

    # A function taking one or more values and returning an array of
    # strings.
    label::Function
end


function identity_formatter(xs::AbstractArray; format=:auto)
    fmt = formatter(xs, fmt=format)
    [fmt(x) for x in xs]
end

const identity_transform =
    ContinuousScaleTransform(identity, identity, identity_formatter)

function log10_formatter(xs::AbstractArray; format=:plain)
    fmt = formatter(xs, fmt=format)
    [@sprintf("10<sup>%s</sup>", fmt(x)) for x in xs]
end

const log10_transform =
    ContinuousScaleTransform(log10, x -> 10^x, log10_formatter)


function log2_formatter(xs::AbstractArray; format=:plain)
    fmt = formatter(xs, fmt=format)
    [@sprintf("2<sup>%s</sup>", fmt(x)) for x in xs]
end

const log2_transform =
    ContinuousScaleTransform(log2, x -> 2^x, log2_formatter)


function ln_formatter(xs::AbstractArray; format=:plain)
    fmt = formatter(xs, fmt=format)
    [@sprintf("e<sup>%s</sup>", fmt(x)) for x in xs]
end

const ln_transform =
    ContinuousScaleTransform(log, exp, ln_formatter)


function asinh_formatter(xs::AbstractArray; format=:plain)
    fmt = formatter(xs, fmt=format)
    [@sprintf("asinh(%s)", fmt(x)) for x in xs]
end

const asinh_transform =
    ContinuousScaleTransform(asinh, sinh, asinh_formatter)


function sqrt_formatter(xs::AbstractArray; format=:plain)
    fmt = formatter(xs, fmt=format)
    [@sprintf("√%s", fmt(x)) for x in xs]
end

const sqrt_transform = ContinuousScaleTransform(sqrt, x -> x^2, sqrt_formatter)


# Continuous scale maps data on a continuous scale simple by calling
# `convert(Float64, ...)`.
immutable ContinuousScale <: Gadfly.ScaleElement
    vars::Vector{Symbol}
    trans::ContinuousScaleTransform
    minvalue
    maxvalue
    format

    function ContinuousScale(vars::Vector{Symbol},
                             trans::ContinuousScaleTransform;
                             minvalue=nothing, maxvalue=nothing,
                             format=nothing)
        new(vars, trans, minvalue, maxvalue, format)
    end
end


function make_labeler(scale::ContinuousScale)
    if scale.format == nothing
        scale.trans.label
    else
        function f(xs)
            scale.trans.label(xs, format=scale.format)
        end
    end
end


const x_vars = [:x, :xmin, :xmax, :xintercept]
const y_vars = [:y, :ymin, :ymax, :yintercept]

function continuous_scale_partial(vars::Vector{Symbol},
                                  trans::ContinuousScaleTransform)
    function f(;minvalue=nothing, maxvalue=nothing, format=nothing)
        ContinuousScale(vars, trans, minvalue=minvalue, maxvalue=maxvalue,
                        format=format)
    end
end


# Commonly used scales.
const x_continuous = continuous_scale_partial(x_vars, identity_transform)
const y_continuous = continuous_scale_partial(y_vars, identity_transform)
const x_log10      = continuous_scale_partial(x_vars, log10_transform)
const y_log10      = continuous_scale_partial(y_vars, log10_transform)
const x_log2       = continuous_scale_partial(x_vars, log2_transform)
const y_log2       = continuous_scale_partial(y_vars, log2_transform)
const x_log        = continuous_scale_partial(x_vars, ln_transform)
const y_log        = continuous_scale_partial(y_vars, ln_transform)
const x_asinh      = continuous_scale_partial(x_vars, asinh_transform)
const y_asinh      = continuous_scale_partial(y_vars, asinh_transform)
const x_sqrt       = continuous_scale_partial(x_vars, sqrt_transform)
const y_sqrt       = continuous_scale_partial(y_vars, sqrt_transform)

const size_continuous = continuous_scale_partial([:size], identity_transform)
const opacity_continuous = continuous_scale_partial([:opacity], identity_transform)


function element_aesthetics(scale::ContinuousScale)
    return scale.vars
end


# Apply a continuous scale.
#
# Args:
#   scale: A continuos scale.
#   datas: Zero or more data objects.
#   aess: Aesthetics (of the same length as datas) to update with scaled data.
#
# Return:
#   nothing
#
function apply_scale(scale::ContinuousScale,
                     aess::Vector{Gadfly.Aesthetics}, datas::Gadfly.Data...)
    for (aes, data) in zip(aess, datas)
        for var in scale.vars
            if getfield(data, var) === nothing
                continue
            end

            ds = Array(Any, length(getfield(data, var)))
            for (i, d) in enumerate(getfield(data, var))
                if isconcrete(d)
                    ds[i] = scale.trans.f(d)
                    i += 1
                else
                    ds[i] = d
                end
            end

            setfield!(aes, var, ds)

            if var in x_vars
                label_var = :x_label
            elseif var in y_vars
                label_var = :y_label
            else
                label_var = symbol(@sprintf("%s_label", string(var)))
            end

            if in(label_var, set(names(aes)))
                setfield!(aes, label_var, make_labeler(scale))
            end
        end

        if scale.minvalue != nothing
            if scale.vars === x_vars
                aes.xviewmin = scale.trans.f(scale.minvalue)
            elseif scale.vars === y_vars
                aes.yviewmin = scale.trans.f(scale.minvalue)
            end
        end

        if scale.maxvalue != nothing
            if scale.vars === x_vars
                aes.xviewmax = scale.trans.f(scale.maxvalue)
            elseif scale.vars === y_vars
                aes.yviewmax = scale.trans.f(scale.maxvalue)
            end
        end
    end
end


# Reorder the levels of a pooled data array
function reorder_levels(da::PooledDataArray, order::AbstractVector)
    level_values = levels(da)
    if length(order) != length(level_values)
        error("Discrete scale order is not of the same length as the data's levels.")
    end
    permute!(level_values, order)
    return PooledDataArray(da, level_values)
end


function discretize(values::Vector, levels=nothing, order=nothing)
    if levels == nothing
        da = PooledDataArray(values)
    else
        da = PooledDataArray(convert(Vector{eltype(levels)}, values), levels)
    end

    if order != nothing
        return reorder_levels(da, order)
    else
        return da
    end
end


function discretize(values::DataArray, levels=nothing, order=nothing)
    if levels == nothing
        da = PooledDataArray(values)
    else
        da = PooledDataArray(convert(DataArray{eltype(levels)}, values), levels)
    end

    if order != nothing
        return reorder_levels(da, order)
    else
        return da
    end
end


function discretize(values::Range1, levels=nothing, order=nothing)
    if levels == nothing
        da = PooledDataArray(collect(values))
    else
        da = PooledDataArray(collect(values), levels)
    end

    if order != nothing
        return reorder_levels(da, order)
    else
        return da
    end
end


function discretize(values::PooledDataArray, levels=nothing, order=nothing)
    if levels == nothing
        da = values
    else
        da = PooledDataArray(values, levels)
    end

    if order != nothing
        return reorder_levels(da, order)
    else
        return da
    end
end


immutable DiscreteScaleTransform
    f::Function
end


immutable DiscreteScale <: Gadfly.ScaleElement
    vars::Vector{Symbol}

    # If non-nothing, give values for the scale. Order will be respected and
    # anything in the data that's not represented in values will be set to NA.
    levels::Union(Nothing, AbstractVector)

    # If non-nothing, a permutation of the pool of values.
    order::Union(Nothing, AbstractVector)

    function DiscreteScale(vals::Vector{Symbol}; levels=nothing, order=nothing)
        new(vals, levels, order)
    end
end

const discrete = DiscreteScale


element_aesthetics(scale::DiscreteScale) = scale.vars


function x_discrete(; levels=nothing, order=nothing)
    return DiscreteScale(x_vars, levels=levels, order=order)
end


function y_discrete(; levels=nothing, order=nothing)
    return DiscreteScale(y_vars, levels=levels, order=order)
end


function apply_scale(scale::DiscreteScale, aess::Vector{Gadfly.Aesthetics},
                     datas::Gadfly.Data...)
    for (aes, data) in zip(aess, datas)
        for var in scale.vars
            label_var = symbol(@sprintf("%s_label", string(var)))

            if getfield(data, var) === nothing
                continue
            end

            disc_data = discretize(getfield(data, var), scale.levels, scale.order)
            setfield!(aes, var, PooledDataArray(int64(disc_data.refs)))

            # The leveler for discrete scales is a closure over the discretized data.
            function labeler(xs)
                lvls = levels(disc_data)
                vals = {1 <= x <= length(lvls) ? lvls[x] : "" for x in xs}
                if all([isa(val, FloatingPoint) for val in vals])
                    format = formatter(vals)
                    [format(val) for val in vals]
                else
                    [string(val) for val in vals]
                end
            end

            if in(label_var, set(names(aes)))
                setfield!(aes, label_var, labeler)
            end
        end
    end
end


immutable DiscreteColorScale <: Gadfly.ScaleElement
    f::Function # A function f(n) that produces a vector of n colors.

    # If non-nothing, give values for the scale. Order will be respected and
    # anything in the data that's not represented in values will be set to NA.
    levels::Union(Nothing, AbstractVector)

    # If non-nothing, a permutation of the pool of values.
    order::Union(Nothing, AbstractVector)

    function DiscreteColorScale(f::Function; levels=nothing, order=nothing)
        new(f, levels, order)
    end
end


function element_aesthetics(scale::DiscreteColorScale)
    [:color]
end


# Common discrete color scales
function discrete_color_hue(; levels=nothing, order=nothing)
    DiscreteColorScale(
        h -> convert(Vector{ColorValue},
             distinguishable_colors(h, ColorValue[LCHab(70, 60, 240)],
                                    lchoices=Float64[65, 70, 75, 80],
                                    cchoices=Float64[0, 50, 60, 70],
                                    hchoices=linspace(0, 330, 24),
                                    transform=c -> deuteranopic(c, 0.5))),
        levels=levels, order=order)
end


const discrete_color = discrete_color_hue


function discrete_color_manual(colors...; levels=nothing, order=nothing)
    cs = ColorValue[color(c) for c in colors]
    function f(n)
        distinguishable_colors(n, cs)
    end
    DiscreteColorScale(f, levels=levels, order=order)
end


function apply_scale(scale::DiscreteColorScale,
                     aess::Vector{Gadfly.Aesthetics}, datas::Gadfly.Data...)
    levelset = Set()
    for (aes, data) in zip(aess, datas)
        if data.color === nothing
            continue
        end
        for d in data.color
            if !isna(d)
                push!(levelset, d)
            end
        end
    end

    if scale.levels == nothing
        scale_levels = [levelset...]
        sort!(scale_levels)
    else
        scale_levels = scale.levels
    end
    if scale.order != nothing
        permute!(scale_levels, scale.order)
    end
    colors = convert(Vector{ColorValue}, scale.f(length(scale_levels)))

    color_map = {color => string(label)
                 for (label, color) in zip(scale_levels, colors)}
    function labeler(xs)
        [color_map[x] for x in xs]
    end


    for (aes, data) in zip(aess, datas)
        if data.color === nothing
            continue
        end
        ds = discretize(data.color, scale_levels)
        colorvals = Array(ColorValue, nonzero_length(ds.refs))
        i = 1
        for k in ds.refs
            if k != 0
                colorvals[i] = colors[k]
                i += 1
            end
        end

        colored_ds = PooledDataArray(colorvals, colors)
        aes.color = colored_ds

        aes.color_label = labeler
        aes.color_key_colors = colors
    end
end


immutable ContinuousColorScale <: Gadfly.ScaleElement
    # A function of the form f(p) where 0 <= p <= 1, that returns a color.
    f::Function

    minvalue
    maxvalue

    function ContinuousColorScale(f::Function; minvalue=nothing, maxvalue=nothing)
        new(f, minvalue, maxvalue)
    end
end


element_aesthetics(::ContinuousColorScale) = [:color]


function continuous_color_gradient(;minvalue=nothing, maxvalue=nothing)
    ContinuousColorScale(
        lab_gradient(LCHab(20, 44, 262), LCHab(100, 44, 262)),
        minvalue=minvalue, maxvalue=maxvalue)
end

const continuous_color = continuous_color_gradient


function apply_scale(scale::ContinuousColorScale,
                     aess::Vector{Gadfly.Aesthetics}, datas::Gadfly.Data...)
    cmin = Inf
    cmax = -Inf
    for data in datas
        if data.color === nothing
            continue
        end

        for c in data.color
            if c === NA
                continue
            end

            c = convert(Float64, c)
            if c < cmin
                cmin = c
            end

            if c > cmax
                cmax = c
            end
        end
    end

    if cmin == Inf || cmax == -Inf
        return nothing
    end

    if scale.minvalue != nothing
        cmin = scale.minvalue
    end

    if scale.maxvalue  != nothing
        cmax = scale.maxvalue
    end

    cmin, cmax = promote(cmin, cmax)

    ticks, viewmin, viewmax = Gadfly.optimize_ticks(cmin, cmax)
    if ticks[1] == 0 && cmin >= 1
        ticks[1] = 1
    end

    cmin = ticks[1]
    cmax = ticks[end]
    cspan = cmax != cmin ? cmax - cmin : 1

    for (aes, data) in zip(aess, datas)
        if data.color === nothing
            continue
        end

        nas = [c === NA for c in data.color]
        cs = Array(ColorValue, length(data.color))
        for (i, c) in enumerate(data.color)
            if c === NA
                continue
            end
            cs[i] = scale.f((convert(Float64, c) - cmin) / cspan)
        end

        aes.color = DataArray(cs, nas)

        color_key_colors = Array(ColorValue, 0)
        color_key_labels = Array(String, 0)

        num_steps = 1
        tick_labels = identity_formatter(ticks)
        for (i, j, label) in zip(ticks, ticks[2:end], tick_labels)
            r = (i - cmin) / cspan
            push!(color_key_colors, scale.f(r))
            push!(color_key_labels, label)

            for step in 1:num_steps
                k = i + (j - i) * (step / (1 + num_steps))
                r = (k - cmin) / cspan
                push!(color_key_colors, scale.f(r))
                push!(color_key_labels, "")
            end
        end
        push!(color_key_colors, scale.f((ticks[end] - cmin) / cspan))
        push!(color_key_labels, tick_labels[end])

        color_key_color_label =
            [c => l for (c, l) in zip(color_key_colors, color_key_labels)]
        function labeler(xs)
            [get(color_key_color_label, x, "") for x in xs]
        end

        aes.color_label = labeler
        aes.color_key_colors = color_key_colors
        reverse!(aes.color_key_colors)
        aes.color_key_continuous = true
    end
end


# Label scale is always discrete, hence we call it 'label' rather
# 'label_discrete'.
immutable LabelScale <: Gadfly.ScaleElement
end


function apply_scale(scale::LabelScale,
                     aess::Vector{Gadfly.Aesthetics}, datas::Gadfly.Data...)
    for (aes, data) in zip(aess, datas)
        if data.label === nothing
            continue
        end

        aes.label = discretize(data.label)
    end
end


element_aesthetics(::LabelScale) = [:label]


const label = LabelScale


# Scale applied to grouping aesthetics.
immutable GroupingScale <: Gadfly.ScaleElement
    var::Symbol
end


function xgroup(; levels=nothing, order=nothing)
    return DiscreteScale([:xgroup], levels=levels, order=order)
end


function ygroup(; levels=nothing, order=nothing)
    return DiscreteScale([:ygroup], levels=levels, order=order)
end


end # module Scale

