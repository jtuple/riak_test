-module(riaknostic_rt).
-export([confirm/0]).
-include_lib("eunit/include/eunit.hrl").

%% Change when a new release comes out.
-define(RIAKNOSTIC_URL, "https://github.com/basho/riaknostic/downloads/riaknostic-1.0.2.tar.gz").

%% riaknostic is not supported on 1.0.3, sigh.
-define(VERSIONS, ["1.1.4", "1.2.0", current]).

confirm() ->
    Passes = lists:map(fun check_on_vsn/1, ?VERSIONS),
    all_pass(Passes).

all_pass([]) ->
    pass;
all_pass([H|T]) ->
    case H =:= pass of 
        false -> fail;
        _ -> all_pass(T)
    end.

check_on_vsn(Version) ->
    %% Build a small cluster
    lager:info("Checking version: ~s", [Version]),
    %%V1 = rt:admin("version"),
    %%lager:info("Version was: ~s", [V1]),
    Nodes = rt:build_cluster(4, [Version, Version, Version, Version], 
                             default),
    [Node1|_Rest] = Nodes, 
    V2 = rt:admin(Node1, ["version"]),
    lager:debug("Version is: ~s", [V2]),
    Result = riaknostic_test(Node1),
    [rt:stop(Node) || Node <- Nodes],
    Result.

riaknostic_install_cmd(LibDir) ->
    Local = rt:get_os_env("LOCAL_RIAKNOSTIC", ""),
    case Local of 
        "" -> 
            Remote = case rt:get_os_env("REMOTE_RIAKNOSTIC", "") of 
                         "" -> ?RIAKNOSTIC_URL;
                         Other -> Other
                     end,
            io_lib:format("sh -c \"cd ~s && curl -O -L ~s && tar xzf ~s\"", 
                          [LibDir, Remote, filename:basename(Remote)]);
        Local -> 
            io_lib:format("sh -c \"cd ~s && ln -s ~s riaknostic\"", 
                          [LibDir, Local])
    end.

riaknostic_test(Node1) ->    
    %% Since we don't have command output matching yet, we'll just
    %% print it to the console and hope for the best.
    lager:info("1. Check download message"),
    {ok, RiaknosticOut1} = rt:admin(Node1, ["diag"]),
    ?assert(rt:str(RiaknosticOut1, "is not present!")),
    %%dut.cmd_output_match('Riak diagnostics utility is not present')

    %% Install
    lager:info("2a. Install Riaknostic"),
    {ok, LibDir} = rpc:call(Node1, application, get_env, [riak_core, platform_lib_dir]),
    Cmd = riaknostic_install_cmd(LibDir),
    lager:info("Running command: ~s", [Cmd]),
    lager:debug("~p~n", [rpc:call(Node1, os, cmd, [Cmd])]),
    
    %% Execute
    lager:info("2b. Check Riaknostic executes"),
    {ok, RiaknosticOut2b} = rt:admin(Node1, ["diag"]),
    ?assertNot(rt:str(RiaknosticOut2b, "is not present!")),
    ?assertNot(rt:str(RiaknosticOut2b, "[debug]")),
    
    %% Check usage message
    lager:info("3. Run Riaknostic usage message"),
    {ok, RiaknosticOut3} = rt:admin(Node1, ["diag", "--help"]),
    ?assert(rt:str(RiaknosticOut3, "Usage: riak-admin")),
    
    %% Check commands list
    lager:info("4. Run Riaknostic commands list message"),
    {ok, RiaknosticOut4} = rt:admin(Node1, ["diag", "--list"]),
    ?assert(rt:str(RiaknosticOut4, "Available diagnostic checks")),
    ?assert(rt:str(RiaknosticOut4, "  disk           ")),
    ?assert(rt:str(RiaknosticOut4, "  dumps          ")),
    ?assert(rt:str(RiaknosticOut4, "  memory_use     ")),
    ?assert(rt:str(RiaknosticOut4, "  nodes_connected")),
    ?assert(rt:str(RiaknosticOut4, "  ring_membership")),
    ?assert(rt:str(RiaknosticOut4, "  ring_preflists ")),
    ?assert(rt:str(RiaknosticOut4, "  ring_size      ")),
    ?assert(rt:str(RiaknosticOut4, "  search         ")),
    ?assert(rt:str(RiaknosticOut4, "  sysctl         ")),
    
    %% Check log levels
    lager:info("5. Run Riaknostic with a different log level"),
    {ok, RiaknosticOut5} = rt:admin(Node1, ["diag", "--level", "debug"]),
    ?assert(rt:str(RiaknosticOut5, "[debug]")),

    %% Check node conn failure when stopped
    lager:info("6. Riaknostic warns of node connection failure when stopped"),
    rt:stop(Node1),
    {ok, RiaknosticOut6} = rt:admin(Node1, ["diag"]),
    ?assert(rt:str(RiaknosticOut6, "[warning] Could not connect")),
    
    %% Check node connection when started
    lager:info("7. Riaknostic connects to node when running"),
    rt:start(Node1),
    {ok, RiaknosticOut7} = rt:admin(Node1, ["diag", "--level", "debug"]),
    ?assert(rt:str(RiaknosticOut7, "[debug] Not connected")),
    ?assert(rt:str(RiaknosticOut7, "[debug] Connected to local Riak node")),
    
    %% Done!
    lager:info("Test riaknostic: PASS"),
    pass.