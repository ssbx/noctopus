-module(sysmo).
-include_lib("common_hrl/include/logs.hrl").

-behaviour(gen_server).

% gen_server
-export([init/1,handle_call/3,handle_cast/2,handle_info/2,
         terminate/2,code_change/3]).

% utils
-export([start_link/0]).

% other
-export([get_pid/1]).

-record(state, {rrd4j_pid, snmp4j_pid, nchecks_pid, assert, ready=false}).

get_pid(For) ->
    gen_server:call(?MODULE, {get_pid, For}).

assert_init() ->
    gen_server:call(?MODULE, assert_init, 10000).

start_link() ->
    Ret = gen_server:start_link({local, ?MODULE}, ?MODULE, [], []),
    % Wait for java side mailbox ready and send the "java_connected"
    % info message.
    ok  = assert_init(),
    Ret.

init([]) ->
    Prefix   = get_java_bin_prefix(),
    Relative = string:concat("sysmo-jserver/bin/sysmo-jserver", Prefix),
    Cmd      = filename:join(
                 filename:absname(get_java_dir()), Relative),
    WorkDir  = filename:absname(""),
    Node     = get_node_name(),
    Cookie   = get_cookie_string(),
    erlang:open_port({spawn_executable, Cmd},
                [{args,[Node, Cookie, WorkDir]},
                 {cd, WorkDir},
                 exit_status,
                 stderr_to_stdout]),
    {ok, #state{}}.

handle_call(assert_init, _From, #state{ready=true} = S) ->
    {reply, ok, S};
handle_call(assert_init, From, S) ->
    {noreply, S#state{assert = From}};

handle_call({get_pid, rrd4j}, _From, #state{rrd4j_pid=Pid} = S) ->
    {reply, Pid, S};
handle_call({get_pid, snmp4j}, _From, #state{snmp4j_pid=Pid} = S) ->
    {reply, Pid, S};
handle_call({get_pid, nchecks}, _From, #state{nchecks_pid=Pid} = S) ->
    {reply, Pid, S};

handle_call(Call, _, S) ->
    ?LOG_WARNING("Received unknow call", Call),
    {noreply, S}.


handle_cast(Cast, S) ->
    ?LOG_WARNING("Received unknow cast", Cast),
    {noreply, S}.


handle_info({java_connected, Rrd4jPid, Snmp4jPid, NchecksPid},
            #state{assert=undefined}) ->
    {noreply, #state{
                 ready = true,
                 rrd4j_pid = Rrd4jPid,
                 snmp4j_pid = Snmp4jPid,
                 nchecks_pid = NchecksPid}};
handle_info({java_connected, Rrd4jPid, Snmp4jPid, NchecksPid},
            #state{assert=From}) ->
    gen_server:reply(From, ok),
    {noreply, #state{
                 ready = true,
                 rrd4j_pid = Rrd4jPid,
                 snmp4j_pid = Snmp4jPid,
                 nchecks_pid = NchecksPid}};

handle_info({_Port, {exit_status, Status}}, S) ->
    ?LOG_ERROR("java node has crashed", {status, Status, state, S}),
    {noreply, S};
    %{stop, "Java node has crashed", S};

handle_info(Info, S) ->
    ?LOG_WARNING("Received unknow info", Info),
    {noreply, S}.


terminate(_,_) ->
    ok.

code_change(_,S,_) ->
     {ok, S}.



% UTILS
get_java_dir() ->
    {ok, Dir} = application:get_env(sysmo, java_dir),
    Dir.

get_java_bin_prefix() ->
    case os:type() of
        {win32,_} -> ".bat";
        {_,_} -> ""
    end.

get_node_name() ->
    erlang:atom_to_list(erlang:node()).

get_cookie_string() ->
    erlang:atom_to_list(erlang:get_cookie()).
