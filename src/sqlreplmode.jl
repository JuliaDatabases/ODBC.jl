import Base: LineEdit, REPL

mutable struct SQLCompletionProvider <: LineEdit.CompletionProvider
    l::REPL.LineEditREPL
end

function return_callback(p::LineEdit.PromptState)
    # TODO ... something less dumb
    buf = take!(copy(LineEdit.buffer(p)))
    # local sp = 0
    # for c in buf
    #   c == '(' && (sp += 1; continue)
    #   c == ')' && (sp -= 1; continue)
    # end
    # sp <= 0
    return true
end

function evaluate_sql(s::String)
    global odbcdf
    global dsn
    try
        odbcdf = ODBC.query(dsn, s)
    catch e
        println(STDOUT, "error during sql evaluation: ", e)
        return nothing
    end
    println(STDOUT, odbcdf)
end

function setup_repl(enabled::Bool)
    # bail out if we don't have a repl
    !isdefined(Base, :active_repl) && return

    repl = Base.active_repl
    main_mode = Base.active_repl.interface.modes[1]

    # disable repl if requested
    if (!enabled)
        delete!(main_mode.keymap_dict, ']')
        return
    end

    panel = LineEdit.Prompt("sql> ";
                            prompt_prefix = Base.text_colors[:white],
                            prompt_suffix = main_mode.prompt_suffix,
                            on_enter = return_callback)

    hp = main_mode.hist
    hp.mode_mapping[:sql] = panel
    panel.hist = hp
    panel.on_done = REPL.respond(evaluate_sql, repl, panel;
                                 pass_empty = false)
    panel.complete = nothing

    sql_keymap = Dict{Any,Any}(
        ']' =>
            function (s,args...)
                if isempty(s) || position(LineEdit.buffer(s)) == 0
                    buf = copy(LineEdit.buffer(s))
                    LineEdit.transition(s, panel) do
                        LineEdit.state(s, panel).input_buffer = buf
                    end
                else
                    LineEdit.edit_insert(s, ']')
                end
            end)

    search_prompt, skeymap = LineEdit.setup_search_keymap(hp)
    mk = REPL.mode_keymap(main_mode)
    b = Dict{Any,Any}[skeymap, mk, LineEdit.history_keymap, LineEdit.default_keymap, LineEdit.escape_defaults]
    panel.keymap_dict = LineEdit.keymap(b)

    main_mode.keymap_dict = LineEdit.keymap_merge(main_mode.keymap_dict, sql_keymap)
    nothing
end

toggle_sql_repl(; enabled::Bool = true) = setup_repl(enabled)