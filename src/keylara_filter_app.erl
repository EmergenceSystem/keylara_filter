%%%-------------------------------------------------------------------
%%% @doc KeyLARA cryptographic entropy agent.
%%%
%%% Exposes the full KeyLARA public API as an em_disco agent.
%%%
%%% === Actions (JSON body field: "action") ===
%%%
%%%   get_entropy_bytes   — N cryptographically secure random bytes,
%%%                         base64-encoded.
%%%                         Param: "n" (integer, default 32).
%%%
%%%   get_version         — Current KeyLARA version string.
%%%
%%%   get_network_pid     — Status of the running ALARA entropy pool
%%%                         supervisor (pid or not_running).
%%%
%%%   start               — Start KeyLARA and its dependencies.
%%%
%%%   stop                — Stop KeyLARA.
%%%
%%% Default (no action): get_entropy_bytes with n=32.
%%%
%%% Handler contract: handle/2 (Body, Memory) -> {RawList, Memory}.
%%% @end
%%%-------------------------------------------------------------------
-module(keylara_filter_app).
-behaviour(application).

-export([start/2, stop/1]).
-export([handle/2, base_capabilities/0]).

%%====================================================================
%% Capability cascade
%%====================================================================

-spec base_capabilities() -> [binary()].
base_capabilities() ->
    em_filter:base_capabilities() ++ [<<"keylara">>, <<"entropy">>,
                                      <<"crypto">>, <<"random">>,
                                      <<"erlang">>].

%%====================================================================
%% Application lifecycle
%%====================================================================

start(_Type, _Args) ->
    case keylara_filter_sup:start_link() of
        {ok, Pid} ->
            ok = start_pop_and_http(),
            {ok, Pid};
        Error ->
            Error
    end.

stop(_State) ->
    catch cowboy:stop_listener(keylara_filter_query_listener),
    catch em_pop_sup:stop_node(keylara_filter),
    ok.

%%====================================================================
%% Internal
%%====================================================================

start_pop_and_http() ->
    PopPort   = application:get_env(keylara_filter, pop_port,   9452),
    QueryPort = application:get_env(keylara_filter, query_port, 9453),
    Seeds     = application:get_env(keylara_filter, pop_seeds,  []),
    Vec = em_filter_vec:from_capabilities(base_capabilities()),
    catch em_pop_sup:stop_node(keylara_filter),
    catch cowboy:stop_listener(keylara_filter_query_listener),
    {ok, PopPid} = em_pop_sup:start_node(keylara_filter, #{
        port            => PopPort,
        query_port      => QueryPort,
        vector          => Vec,
        max_peers       => 100,
        gossip_interval => 5_000
    }),
    lists:foreach(
        fun({H, P}) -> catch em_pop_node:add_peer(PopPid, H, P) end,
        Seeds),
    Dispatch = cowboy_router:compile([
        {'_', [{"/agent/query", em_filter_http,
                #{server => keylara_filter_server}}]}
    ]),
    {ok, _} = cowboy:start_clear(keylara_filter_query_listener,
                                  [{port, QueryPort}],
                                  #{env => #{dispatch => Dispatch}}),
    logger:notice("[keylara_filter] gossip port ~w  query port ~w",
                  [PopPort, QueryPort]),
    ok.

handle(Body, Memory) when is_binary(Body) ->
    {dispatch(Body), Memory};
handle(_Body, Memory) ->
    {[], Memory}.

%%====================================================================
%% Dispatch
%%====================================================================

dispatch(Body) ->
    Params = decode_params(Body),
    case maps:get(<<"action">>, Params, <<"get_entropy_bytes">>) of
        <<"get_entropy_bytes">> ->
            N = get_int(<<"n">>, Params, 32),
            [entropy_embryo(keylara:get_entropy_bytes(N), N)];
        <<"get_version">> ->
            Version = keylara:get_version(),
            [version_embryo(Version)];
        <<"get_network_pid">> ->
            [network_pid_embryo(keylara:get_network_pid())];
        <<"start">> ->
            [start_embryo(keylara:start())];
        <<"stop">> ->
            keylara:stop(),
            [ok_embryo(<<"stop">>)];
        _ ->
            N = get_int(<<"n">>, Params, 32),
            [entropy_embryo(keylara:get_entropy_bytes(N), N)]
    end.

%%====================================================================
%% Embryo builders
%%====================================================================

entropy_embryo({ok, Bytes}, N) when is_binary(Bytes) ->
    #{<<"properties">> => #{
        <<"url">>    => <<"https://hex.pm/packages/keylara">>,
        <<"title">>  => iolist_to_binary(
                            io_lib:format("~B entropy bytes", [N])),
        <<"resume">> => base64:encode(Bytes),
        <<"source">> => <<"keylara">>
    }};
entropy_embryo({error, Reason}, _N) ->
    error_embryo(<<"get_entropy_bytes">>, Reason).

version_embryo(Version) ->
    #{<<"properties">> => #{
        <<"url">>    => <<"https://hex.pm/packages/keylara">>,
        <<"title">>  => <<"KeyLARA version">>,
        <<"resume">> => list_to_binary(Version),
        <<"source">> => <<"keylara">>
    }}.

network_pid_embryo({ok, Pid}) ->
    #{<<"properties">> => #{
        <<"url">>    => <<"https://hex.pm/packages/keylara">>,
        <<"title">>  => <<"ALARA network supervisor">>,
        <<"resume">> => iolist_to_binary(io_lib:format("~p", [Pid])),
        <<"source">> => <<"keylara">>
    }};
network_pid_embryo({error, Reason}) ->
    error_embryo(<<"get_network_pid">>, Reason).

start_embryo(ok) ->
    ok_embryo(<<"start">>);
start_embryo({error, Reason}) ->
    error_embryo(<<"start">>, Reason).

ok_embryo(Action) ->
    #{<<"properties">> => #{
        <<"url">>    => <<"https://hex.pm/packages/keylara">>,
        <<"title">>  => iolist_to_binary(
                            io_lib:format("keylara ~s", [Action])),
        <<"resume">> => <<"ok">>,
        <<"source">> => <<"keylara">>
    }}.

error_embryo(Action, Reason) ->
    #{<<"properties">> => #{
        <<"url">>    => <<"https://hex.pm/packages/keylara">>,
        <<"title">>  => iolist_to_binary(
                            io_lib:format("error: ~s", [Action])),
        <<"resume">> => iolist_to_binary(io_lib:format("~p", [Reason])),
        <<"source">> => <<"keylara">>
    }}.

%%====================================================================
%% Helpers
%%====================================================================

decode_params(Body) ->
    try json:decode(Body) of
        Map when is_map(Map) -> Map;
        _                    -> #{}
    catch _:_ -> #{} end.

get_int(Key, Params, Default) ->
    case maps:get(Key, Params, Default) of
        V when is_integer(V), V > 0 -> V;
        B when is_binary(B) ->
            try binary_to_integer(B) catch _:_ -> Default end;
        _ -> Default
    end.
