format compact
format long

Num_arrivals = 1e5;


service_rate = 10e9 / (1500 * 8);
% service_times = generate_exp_service_times (service_rate, Num_arrivals);
service_times = ones(Num_arrivals,1) / service_rate; % deterministic


% % D0 = [-1,0.4;0.8,-1];
% % D1 = [0.4,0.2;0.1,0.1];
% % D0 = [-50.99,0.99;0.01,-0.01];
% % D1 = [50,0;0,0];
% D0 = rand(4)/2;
% D1 = rand(4)/2;
% D0 = D0 - diag(diag(D0));
% D0 = D0 - diag(sum(D0+D1,2));
% Q = D0 + D1;
% steady_state_distr = [1, zeros(1,size(D0,1)-1)] / [ones(size(D0,1),1),Q(:,2:end)];
% disp(['arrival rate: ', num2str(sum(steady_state_distr*D1))])
% arrival_times = generate_map_arrivals (D0, D1, Num_arrivals);


arrival_rate = service_rate * load;

% burstiness = 0;
D0 = [-(burstiness+arrival_rate*(burstiness+1)),burstiness;1,-1];
D1 = [arrival_rate*(burstiness+1),0;0,0];
arrival_times = generate_map_arrivals (D0, D1, Num_arrivals);

% arrival_times = generate_poisson_arrivals (arrival_rate, Num_arrivals);


% trace file
M = readmatrix('BC-pAug89.TL.txt');
arrival_times = M(:,1);
Num_arrivals = length(arrival_times);
data_rate = 2e6; % bps
service_times = M(:,2)*8 / data_rate;
load = sum( M(:,2)*8 ) / ( M(end,1) * data_rate );
arrival_rate = M(end,1) / Num_arrivals;



% enum states
state_active = 0;
state_lpi = 1;
state_waking = 2;
state_sleeping = 3;

% enum events
event_arrival = 0;
event_departure = 1;
event_sleep = 2;
event_wake_up = 3;
event_time_out = 4;

% EEE parameters
sleep_time = 4.48e-6; % Ts
wake_up_time = 2.88e-6; % Tw
max_packets_to_coalesce = 10;
coalesce_timer = 12e-6;

% init
% % % %%% | event time | packet index | event type | processed? |
% % % event_list = [arrival_times, (1:Num_arrivals)', event_arrival*ones(Num_arrivals,1), zeros(Num_arrivals,1)];
%%% | event time | packet index | event type |
event_list = [arrival_times, (1:Num_arrivals)', event_arrival*ones(Num_arrivals,1)];
ethernet_state = state_lpi;
event_list = sortrows([coalesce_timer, 0, event_time_out; event_list]);
sim_time = 0;
time_active = 0;
time_lpi = 0;
packets_in_queue = 0;
packets_coalesced = [];
departure_times = zeros( size(arrival_times) );
packet_index = 0;
fprintf('%10d',packet_index)
event_list_processed = [];
ppp = packet_index;

while ~isempty(event_list) % packet_index < Num_arrivals
    ppp = max(ppp,packet_index);
    fprintf('\b\b\b\b\b\b\b\b\b\b%10d',ppp)
% % %     disp(ethernet_state)
% % %     disp(packets_in_queue)
% % %     disp(packets_coalesced')
% % %     disp('-------------')
    
    if ethernet_state ~= state_active && packets_in_queue ~= length(packets_coalesced) 
        disp(' yhyhy ')
    end
    if ethernet_state == state_active && ~isempty( find( event_list(:,3) == event_time_out, 1 ) )
        disp(' fdgdfgdfg ')
    end

    % get next unprocessed event
    %%%%%%%%%%%%%%%%%%%%%%event_list_processed = [event_list(1,:);event_list_processed];
    event_time = event_list(1,1);
    packet_index = event_list(1,2);
    event_type = event_list(1,3);
    event_list(1,:) = []; % this event processed

    % update time stats
    if ethernet_state == state_lpi
        time_lpi = time_lpi + event_time - sim_time;
    else % state_waking and state_sleeping act as state_active
        time_active = time_active + event_time - sim_time;
    end

    % advance time
    assert( sim_time < event_time )
    sim_time = event_time;

    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    if event_type == event_arrival
        packets_in_queue = packets_in_queue + 1;
        if ethernet_state ~= state_active
            % either idle, or waking, or going into sleep, cannot serve
            packets_coalesced = [ packets_coalesced; packet_index ];
            assert( packets_in_queue == length(packets_coalesced) )
            if ethernet_state == state_lpi && packets_in_queue >= max_packets_to_coalesce
                assert( ethernet_state == state_lpi )
                % remove timeout events
                event_list( event_list(:,3) == event_time_out, : ) = [];
                % insert wake up event
                if ethernet_state ~= state_waking
                    ethernet_state = state_waking;
                    event_list = sortrows([sim_time + wake_up_time, 0, event_wake_up;...
                        event_list]);
                end
            end
        end
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    elseif event_type == event_departure
        packets_in_queue = packets_in_queue - 1;
        assert( packets_in_queue >= 0 )
        departure_times(packet_index) = sim_time;
        if packets_in_queue == 0
            ethernet_state = state_sleeping;
            event_list = sortrows([sim_time+sleep_time, 0, event_sleep;...
                event_list]);
            if packet_index == Num_arrivals
                % last packet departs, simulation should end
                break
            end
        else
            % generate next departure
            departure_time = sim_time + service_times(packet_index+1);
            event_list = sortrows([departure_time, packet_index+1, event_departure;...
                event_list]);
        end        
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    elseif event_type == event_sleep
        ethernet_state = state_lpi;
        % insert timeout event
        event_list = sortrows([sim_time + coalesce_timer, 0, event_time_out;...
            event_list]);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    elseif event_type == event_time_out
        assert( packets_in_queue == length(packets_coalesced) )
        if packets_in_queue > 0
            % insert wake up event
            ethernet_state = state_waking;
            event_list = sortrows([sim_time + wake_up_time, 0, event_wake_up;...
                event_list]);
        else
            assert( ethernet_state == state_lpi )
            % still no packets, stay idle
            event_list = sortrows([sim_time + coalesce_timer, 0, event_time_out;...
                event_list]);
        end
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    else %if event_type == event_wake_up
        assert( event_type == event_wake_up )
        assert( ~isempty(packets_coalesced) )
        assert( packets_in_queue == length(packets_coalesced) )
        assert( issorted(packets_coalesced) )
        ethernet_state = state_active;
        % start serving coalesced packets, i.e. generate departure of the head of queue
        packet_index = packets_coalesced(1);
        packets_coalesced = [];
        departure_time = sim_time + service_times( packet_index );
        event_list = sortrows([departure_time, packet_index, event_departure;...
            event_list]);
    end
end

% disp(' ')
% disp( ['idle ratio: ', num2str( time_lpi/(time_lpi+time_active) )] )
% disp( ['mean delay: ', num2str( mean(departure_times-arrival_times) )] )


disp([load, burstiness, time_lpi/(time_lpi+time_active), mean(departure_times-arrival_times)])





function arrival_times = generate_poisson_arrivals (arrival_rate, Num_arrivals)
     arrival_times = cumsum( exprnd (1/arrival_rate, Num_arrivals, 1) );
end

function arrival_times = generate_deterministic_arrivals (arrival_rate, Num_arrivals)
     arrival_times = (1:Num_arrivals)' / arrival_rate;
end

function arrival_times = generate_map_arrivals (D0, D1, Num_arrivals)
     assert ( size(D0,1) == size(D0,2), 'Error: D0 not square' )
     assert ( size(D1,1) == size(D1,2), 'Error: D1 not square' )
     assert ( size(D0,1) == size(D1,1), 'Error: D0 and D1 have different sizes' )
     assert ( all( diag(D0) <= 0 ), 'Error: D0 has pos diagonal element' )
     assert ( all( all( D0-diag(diag(D0)) >= 0 ) ), 'Error: D0 has neg off-diagonal element' )
     assert ( all( all( D1 >= 0 ) ), 'Error: D1 has neg element' )
     %%%%%%%%%%%assert ( all(sum(D0+D1,2) < 1e-12), 'Error: D0+D1 is not inf gen' )
     arrival_times = zeros(Num_arrivals,1);
     number_of_states = size(D0,1);
     index = 1;
     t = 0;
     Q = D0 + D1;
     steady_state_distr = [1, zeros(1,size(D0,1)-1)] / [ones(size(D0,1),1),Q(:,2:end)];
%      disp(['arrival rate: ', num2str(sum(steady_state_distr*D1))])
     state = 1;%find ( rand < cumsum(steady_state_distr), 1 );
     while index <= Num_arrivals
         q = [D0(state,:), D1(state,:)];
         holding_time = exprnd(-1/q(state));
         t = t + holding_time;
         q(state) = 0;
         next_state = find( rand < cumsum(q/sum(q)), 1 );
         if next_state > number_of_states
             arrival_times(index) = t;
             index = index + 1;
             next_state = next_state - number_of_states;
         end
         state = next_state;
     end     
end







function service_times = generate_exp_service_times (service_rate, Num_arrivals)
     service_times = exprnd (1/service_rate, Num_arrivals, 1);
end

