% This file is part of "Enms" (http://sourceforge.net/projects/enms/)
% Copyright (C) 2012 <Sébastien Serre sserre.bx@gmail.com>
% 
% Enms is a Network Management System aimed to manage and monitor SNMP
% targets, monitor network hosts and services, provide a consistent
% documentation system and tools to help network professionals
% to have a wide perspective of the networks they manage.
% 
% Enms is free software: you can redistribute it and/or modify
% it under the terms of the GNU General Public License as published by
% the Free Software Foundation, either version 3 of the License, or
% (at your option) any later version.
% 
% Enms is distributed in the hope that it will be useful,
% but WITHOUT ANY WARRANTY; without even the implied warranty of
% MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
% GNU General Public License for more details.
% 
% You should have received a copy of the GNU General Public License
% along with Enms.  If not, see <http://www.gnu.org/licenses/>.
% @doc
% This module log data to an rrd database. Data must exist in the
% #probe_return.key_val record.
% To work a valid #rrd_def record must be givent at init conf input.
% @end
-module(bmonitor_logger_rrd3).
-behaviour(monitor_logger).
-include("include/monitor.hrl").

-export([
    log_init/2,
    log/2,
    dump/2
]).

-record(state, {
    type,
    rrd_update,
    row_index_to_tpl,
    row_index_to_file,
    %% for dump
    target_name,
    probe_name,
    dump_dir
}).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% INIT (rrdcreate) %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
log_init(Conf, Probe) ->
    [Target]        = monitor_data_master:get(target, Probe#probe.belong_to),
    ConfType        = proplists:get_value(type, Conf),
    {ok, DumpDir}   = application:get_env(supercast, http_sync_dir),
    case ConfType of
        snmp_table ->
            % the return will be from a walk_table method
            % get the create rrd string
            RrdCreateStr    = proplists:get_value(rrd_create, Conf),
            % get the list of index to file bind. Index is the second element
            % of a table element returned by the walk_table method. It must
            % uniquely identify the table row.
            TargetDir       = proplists:get_value(var_directory, Target#target.sys_properties),
            IndexesRrd      = proplists:get_value(row_index_to_rrd_file, Conf),
            IndexesRrdPaths = build_rrd_file_paths(TargetDir, IndexesRrd),
            snmp_table_init_rrd_files(RrdCreateStr, IndexesRrdPaths),
 
            IndexesTpl = proplists:get_value(row_index_pos_to_rrd_template, Conf),
            RrdUpdate  = proplists:get_value(rrd_update, Conf),

            {ok,
                #state{
                    type                = ConfType,
                    rrd_update          = RrdUpdate,
                    row_index_to_file   = IndexesRrdPaths,
                    row_index_to_tpl    = IndexesTpl,
                    target_name         = Target#target.name,
                    probe_name          = Probe#probe.name,
                    dump_dir            = DumpDir
                }
            };
        _ ->
            {ok, nostate}
    end.

build_rrd_file_paths(TargetDir, Indexes) ->
    build_rrd_file_paths(TargetDir, Indexes, []).
build_rrd_file_paths(_, [], Acc) -> Acc;
build_rrd_file_paths(TargetDir, [{Id, File}|Rest], Acc) ->
    FPath = filename:join(TargetDir, File),
    build_rrd_file_paths(TargetDir, Rest, [{Id,FPath}|Acc]).

% @doc
% Create rrdfiles for return sent from a walk_table method.
% @end
snmp_table_init_rrd_files(RrdCreateStr, IndexToFile) ->
    RrdCreate = snmp_table_build_create(RrdCreateStr, IndexToFile, []),
    lists:foreach(fun(X) -> errd:create(X) end, RrdCreate).

snmp_table_build_create(_, [], Acc) -> Acc;
snmp_table_build_create(RrdCreate,[{_,File}|T],Acc) ->
    case filelib:is_file(File) of
        true ->
            snmp_table_build_create(RrdCreate, T, Acc);
        false ->
            RrdCmd = lists:concat([File, RrdCreate]),
            snmp_table_build_create(RrdCreate, T, [RrdCmd|Acc])
    end.


%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% LOG (rrdupdate) %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
log(State, #probe_return{reply_tuple = ignore} = _ProbeReturn) ->
    ClientUp = [{I, ""} || {I,_} <- State#state.row_index_to_file],
    Pdu = monitor_pdu:loggerRrdEvent(State#state.target_name, State#state.probe_name, ClientUp),
    {ok, Pdu, State};

log(State, #probe_return{reply_tuple = Rpl, timestamp = Ts} = _ProbeReturn) ->
    RIndexFile = State#state.row_index_to_file,
    RIndexTpl  = State#state.row_index_to_tpl,
    RrdUpdate  = State#state.rrd_update,
    {ok, ClientUp} = rrd_update(RIndexFile, RIndexTpl, RrdUpdate, Rpl, Ts),
    Pdu = monitor_pdu:loggerRrdEvent(State#state.target_name, State#state.probe_name, ClientUp),
    {ok, Pdu, State}.

rrd_update(RindexFile, RIndexTpl, RrdUpdate, Rpl, Ts) ->
    rrd_update(RindexFile, RIndexTpl, RrdUpdate, Rpl, Ts, []).
rrd_update([],_,_,_,_, Acc) -> {ok, Acc};
rrd_update([{Index, File}|Tail], RIndexTpl, RrdUpdate, Rpl, Ts, Acc) ->
    {value, Row, Rpl2} = lists:keytake(Index, 2, Rpl),
    TplString = rrd_update_build_tpl(RIndexTpl, Row, Ts),
    RrdCmd = lists:concat([File, " ", RrdUpdate, " ", TplString]),
    errd:update(RrdCmd),
    rrd_update(Tail, RIndexTpl, RrdUpdate, Rpl2, Ts, [{Index,TplString}|Acc]).

rrd_update_build_tpl([], _, Acc) -> Acc;
rrd_update_build_tpl([I|T], Row, Acc) ->
    Val = erlang:element(I, Row),
    rrd_update_build_tpl(T,Row, lists:concat([Acc, ":", Val])).





%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%% DUMP (rrddump) %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
dump(#state{row_index_to_file = RI, dump_dir = DDir} = State, Caller) ->
    Dir     = lists:concat(["tmp-", generate_tmp_dir()]),
    Path    = filename:join(DDir, Dir),

    % BEGIN delayed dump
    dump_delayed(Path, Dir, RI, State, Caller),
    % END delayed dump

    {ignore, State}.

dump_delayed(Path, Dir, RowIndex, State, Caller) ->
    ok = file:make_dir(Path),
    IndexToFile = dump_delayed_fill_dir(RowIndex, Path),
    Pdu = monitor_pdu:loggerRrdDump(
        State#state.target_name, State#state.probe_name, ?MODULE, IndexToFile, Dir),
    Fun = fun() ->
        supercast_channel:unicast(Caller, [Pdu])
    end,
    errd:dump_delayed(Path, Fun).


dump_delayed_fill_dir(RIndex, DirEx) ->
    dump_delayed_fill_dir(RIndex, DirEx, []).
dump_delayed_fill_dir([], _, Acc) -> Acc;
dump_delayed_fill_dir([{I,F} | T], DirEx, Acc) ->
    % F is /var/somthing/jojo1.rrd

    % BaseName will be jojo1.rrd
    BaseName    = filename:basename(F),

    % DestFile will be /dest/dir/jojo1.rrd
    DestFile    = filename:join(DirEx, BaseName),

    % XmlFile will be jojo1.rrd.xml
    XmlFile     = lists:concat([BaseName, ".xml"]),

    file:copy(F, DestFile),
    dump_delayed_fill_dir(T, DirEx, [{I,XmlFile}|Acc]).


generate_tmp_dir() ->
    {_, Sec, Micro} = os:timestamp(),
    Microsec = Sec * 1000000 + Micro,
    Microsec.
