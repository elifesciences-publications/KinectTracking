%Script to track the color markers over time 
%Originally written by Joshua Glaser

%This script loads a file that contains the locations of the color pixels of each frame, and
%uses that to determine the marker locations at every frame

%In general, tracking works by finding points that are near the marker in
%the previous frame, along with using constraints based on distances to
%other markers.

%The general flow of the script is as follows:
%1) Initializations
%2) Select the marker locations in the "start" frame
%3) Get the location of the arm markers
%The red arm markers are run a preliminary time, in order to get distance
%constraints from the blue arm marker
%Some manual correction is allowed for the elbow markers (of frames that
%get automatically flagged)
%4) Get the location of the hand markers a preliminary time (in order to set
%distance constraints between the hand and arm markers)
%5) Set the distance constraints (mentioned above) between the hand markers
%and arm markers
%6) Get the location of the hand markers (except the yellow one), using distance constraints
%7) Do manual correction of hand markers (for frames that get automatically flagged)
%8) Get the location of the yellow hand marker
%This is done after correcting the other hand markers, because it is noisy (sometimes green triggers the
%yellow detector), and we use the other hand markers as constraints for
%finding the yellow marker
%9) Do some additional correction of hand points not based on distances
%from arm markers (in case there are frames the arm markers were missing)
%10) Clean up data a little, and save

%For the main tracking portions of the script (e.g. blue arm, red hand,
%etc.), there are more detailed comments in the "Blue Arm" section which
%comes first. For the subsequent sections, only unique aspects are
%commented on in detail.

%% 1. INITIALIZATIONS %%%%%%%%%%%%%%%%%%
try
if ~exist('section_completed','var') || section_completed<=1
    %% Input File to Load
    
    % NOW LOADING FILE OUTSIDE THIS SCRIPT
    
    % Rename data from loaded file (if it's in the new format)
    
        
    if exist('color_coords_allframes','var')
        color1=color_coords_allframes(:,3)'; % Marker colors 1 and 3 were switched in python script at some point
        color2=color_coords_allframes(:,2)';
        color3=color_coords_allframes(:,1)';
        color4=color_coords_allframes(:,4)';
    end
    
    %% User Options / Initializations
    
    %Save the output?
    savefile=1;
    
    %Use all default values for constraints (mostly for distances between markers)
    use_defaults= 0;
    
    %If this is the first file from a date, set equal to 1 (there are more initializations)
    %Also, if you have use_defaults=1, set this equal to 1
    % first_time=1;
    
    %TIME INITIALIZATIONS
    if ~exist('start','var')
        start=1; %Time point we're starting at. Importantly, this script is
        %currently set up to require that all markers are visible during the "start" frame.
        %Thus, the user can use  the script "original_colors_plots_4colors" to find
        %the first frame where all markers are visible.
    end
    
    n=length(color1);
    finish=n; %Time point we're finishing at
    n_times=finish-start+1; %Number of time points (frames)
    
    n_times_prelim=round(3*n/4); %Number of time points to run in order to set distance limits (using all frames is not necessary and will take longer)
    %If you set "use_defaults" to 1, it's better to make this larger, so it has
    %more data to accurately set the defaults.
    finish_prelim=start+n_times_prelim-1;
    
    %Plot figure of schematic of marker locations?
    plot_marker_locs=1;
    
    %MARKER NUMBER INITIALIZATIONS
    red_arm_marker_ids=[8,10];
    blue_arm_marker_ids=[7];
    green_shoulder_marker_ids=[9];
    green_elbow_marker_ids=[6];
    red_hand_marker_ids=[3];
    yellow_hand_marker_ids=[4];
    blue_hand_marker_ids=[2];
    green_hand_marker_ids=[1,5];
    
    %% Plotting Initializations (Also User Input)
    
    plot_during=0; %If you'll be displaying the marker tracking while it's running at any point (only used during testing)
    
    %The x and y limits matter for selecting the markers in the initial frame.
    %The z limit will only matter if plot_during=1
    xlims=[-.5 .5];
    ylims=[-.5 .4];
    zlims=[.25 1.25];
    pause_time=.03;
    
    if plot_during
        figure;
        set(gca,'NextPlot','replacechildren');
    end
    
    %% Initializations of vectors/matrices
    
    %Keeps track of all the cluster locations
    all_medians=NaN(11,3,n_times); %Has NaNs when a marker is missing
    all_medians2=NaN(11,3,n_times); %Estimates where markers are when they are missing
    
    %Initialize some vectors that I use later for calculating the distance
    %between points
    dists=NaN(1,n_times_prelim);
    dists1=NaN(1,n_times_prelim);
    dists2=NaN(1,n_times_prelim);
    dists3=NaN(1,n_times_prelim);
    dists4=NaN(1,n_times_prelim);
    dists5=NaN(1,n_times_prelim);
    
    %log file
    section_completed = 1;
end

%% 2. SELECT THE INITIAL MARKER LOCATIONS IN THE "START" FRAME
if ~exist('section_completed','var') || section_completed<2
    %% Marker location schematic figure
    
    %This produces a schematic figure of the marker locations, colors, and
    %numbers.
    
    marker_demo_locs=[0 0; 1 1; 1 -1; 2 1; 2 -1;...
        10 -1; 10 3; 10 6; 10 9; 9 0;...
        2 -3];
    r=[1 0 0];
    g=[0 1 0];
    b=[0 1 1];
    y=[1 1 0];
    marker_demo_colors=[g; b; r; y; g; g; b; r; g; r; b];
    
    figure('units','normalized','outerposition',[0 0 1 1])
    subplot(1,2,1);
    scatter(marker_demo_locs(:,1),marker_demo_locs(:,2),200,marker_demo_colors,'filled');
    str={'1','2','3','4','5','6','7','8','9','10','11'};
    text(marker_demo_locs(:,1),marker_demo_locs(:,2),str)
    xlim([-5 15]);
    ylim([-5 15]);
    
    %% Marker location initializations (interactive)
    
    %We here set the locations of the markers in the "start" frame
    
    marker_colors={'g','b','r','y','g','g','b','r','g','r'}; %The colors of each of our markers
    
    num_markers=10;
    marker_coords_xy=NaN(num_markers,2);
    
    %Get x,y,z coordinates for points in all colors
    [x1,y1,z1] = getXYZfromKinect(color1{start});
    [x2,y2,z2] = getXYZfromKinect(color2{start});
    [x3,y3,z3] = getXYZfromKinect(color3{start});
    [x4,y4,z4] = getXYZfromKinect(color4{start});
    
    %Plot all the points in the x/y plane (z, which is depth, doesn't change
    %much between the points)
    subplot(1,2,2);
    scatter(x1,y1,'b')
    hold on;
    scatter(x2,y2,'g')
    scatter(x3,y3,'r')
    scatter(x4,y4,'y')
    hold off
    xlabel('x')
    ylabel('y')
    xlim(xlims)
    ylim(ylims)
    
    %Have users select the markers
    for m=1:num_markers
        title(['Click marker ' num2str(m)])
        marker_coords_xy(m,:)=ginput(1);
    end
    
    %Get the 3d marker locations. To do so, we find the point (of the appropriate color) with the
    %closest x/y coordinate. We then get the x/y/z coordinates of that point.
    marker_inits=NaN(11,3); %Made large enough for an 11th marker (which we used at one point)
    for m=1:num_markers
        if marker_colors{m}=='r'
            closest_point=knnsearch([x3' y3'],marker_coords_xy(m,:),'k',1);
            marker_inits(m,:)=[x3(closest_point) y3(closest_point) z3(closest_point)];
        end
        if marker_colors{m}=='g'
            closest_point=knnsearch([x2' y2'],marker_coords_xy(m,:),'k',1);
            marker_inits(m,:)=[x2(closest_point) y2(closest_point) z2(closest_point)];
        end
        if marker_colors{m}=='b'
            closest_point=knnsearch([x1' y1'],marker_coords_xy(m,:),'k',1);
            marker_inits(m,:)=[x1(closest_point) y1(closest_point) z1(closest_point)];
        end
        if marker_colors{m}=='y'
            closest_point=knnsearch([x4' y4'],marker_coords_xy(m,:),'k',1);
            marker_inits(m,:)=[x4(closest_point) y4(closest_point) z4(closest_point)];
        end
    end
    
    %log file
    section_completed = 2;
end
        
%% 3. TRACK ARM MARKERS (GET THE LOCATION OF ARM MARKERS)
if ~exist('section_completed','var') || section_completed<=3
    %% Blue Arm (make this a <function>?)
    
    %Initializations
    plot_on=0; %Whether to plot while it's running
    marker_ids=blue_arm_marker_ids; %Set the marker_ids specified in "Initializations"
    color=color1; %Blue=1, Green=2, Red=3
    prev_meds=marker_inits(marker_ids,:); %Set initial "previous marker locations" as the start locations input in "Initializations"
    num_clust=length(marker_ids); %Number of clusters
    within_clust_dist1=0.07; %How close points must be to the previous frame's marker to be considered
    dist_min=0.07; %Minimum distance between markers (cluster medians aren't allowed w/ distance < min_dist)
    
    medians=NaN(num_clust,3,n_times); %Has NaNs when a marker is missing
    medians2=NaN(num_clust,3,n_times); %Has previous known positions when a marker is missing
    
    
    % LOOP THROUGH TIME
    if section_completed <2.1
    t=0;
    prev_num_clust=num_clust;
    for i=start:finish
        
        t=t+1;
        
        %0. Get x,y,z positions
        [x,y,z] = getXYZfromKinect(color{i});
        loc=[x; y; z]';
        
        if ~isempty(loc)
            %1. Filter some bad points (those that are really far away)
            %Get distances of all points to the marker in the previous frame
            if t==1
                D=pdist2(loc,prev_meds);
            else
                D=pdist2(loc,medians2(:,:,t-1));
            end

            % Keep all the points close enough to the previous marker
            keep1=D(:,1)<within_clust_dist1;

            %Remove points (those we're not keeping)
            rmv=~(keep1);

            %Actually remove the points
            loc(rmv,:)=[];
        end
        
        %2. Cluster and assign
        [ prev_num_clust, prev_meds, medians, medians2  ] = cluster_func2(t, loc, num_clust, prev_num_clust, dist_min, prev_meds, medians, medians2, 1 );
        
        %3. Plot original image and cluster centers
        plot_clusts( plot_on, num_clust, x, y, z, medians, i, t, pause_time, xlims, ylims, zlims )
        
    end

    section_completed = 2.1;
    
    
    %Put the markers found here in the matrix of all markers
    all_medians(marker_ids,:,:)=medians;
    all_medians2(marker_ids,:,:)=medians2;
    end
    %% Red Arm (Preliminary)
    if section_completed <2.2
    if first_time %If this is not the first file from a date, we don't need to run this.
        
        %Initializations
        plot_on=0;
        marker_ids=red_arm_marker_ids;
        color=color3;
        prev_meds=marker_inits(marker_ids,:);
        num_clust=length(marker_ids);
        within_clust_dist1=.07; %How close points must be to the previous frame's first marker, # marker_ids(1), to be considered
        within_clust_dist2=.07; %How close points must be to the previous frame's second marker, # marker_ids(2), to be considered
        dist_min=0.004;
        
        medians=NaN(num_clust,3,n_times);
        medians2=NaN(num_clust,3,n_times);
        
        % LOOP THROUGH TIME
        t=0;
        prev_num_clust=num_clust;
        for i=start:finish
            
            t=t+1;
            
            %0. Get x,y,z positions
            [x,y,z] = getXYZfromKinect(color{i});
            loc=[x; y; z]';
            
            if ~isempty(loc)
                %1. Filter some bad points (those that are really far away)
                %Get distances of all points to the marker in the previous frame
                if t==1
                    D=pdist2(loc,prev_meds);
                else
                    D=pdist2(loc,medians2(:,:,t-1));
                end

                % Keep all the points close enough to either of the previous markers
                keep1=D(:,1)<within_clust_dist1;
                keep2=D(:,2)<within_clust_dist2;

                %Remove points (those we're not keeping)
                rmv=~(keep1 | keep2);

                %Actually remove the points
                loc(rmv,:)=[];
            end
            
            %2. Cluster and assign
            %Note that this uses "cluster_func" instead of "cluster_func2"
            %which is slightly faster but less accurate. This is because we
            %will be redoing this later with cluster_func2. This current run is
            %only to determine the distances from the red arm to blue arm
            %markers (which will help in the next run)
            [ prev_num_clust, prev_meds, medians, medians2  ] = cluster_func(t, loc, num_clust, prev_num_clust, dist_min, .05, prev_meds, medians, medians2 );
            
            %3. Plot original image and cluster centers
            plot_clusts( plot_on, num_clust, x, y, z, medians, i, t, pause_time, xlims, ylims, zlims )
            
        end
        
        %Put the markers found here in the matrix of all markers
        all_medians(marker_ids,:,:)=medians;
        all_medians2(marker_ids,:,:)=medians2;
        
    end

    section_completed = 2.2;
    end
    %% Set limits on red arm to blue arm distances
    if section_completed <2.3
    %PLOT RED ARM TO BLUE ARM DISTANCES
    if first_time %If this is not the first file from a date, we don't need to run this.
        
        %Calculate distances for each time point
        for i=1:n_times_prelim
            dists(i)=pdist2(all_medians(10,:,i),all_medians(7,:,i)); %Distance between markers 7 and 10 (blue arm and red elbow)
            dists2(i)=pdist2(all_medians(8,:,i),all_medians(7,:,i)); %Distance between markers 7 and 8 (blue arm and red arm)
        end
        
        if use_defaults %User defaults
            red_elbow_dist_from_blue=nanmean(dists)+4*nanstd(dists);
            red_blue_arm_dist_max=nanmean(dists2)+4*nanstd(dists2);
            
        else %If not using defaults
            
            %Plot
            figure; plot(dists);
            hold on;
            plot(dists2)
            legend('7-10','7-8')
            title('Distance between blue arm marker (7) and red arm markers (8 and 10)');
            
            %VISUALIZE FRAMES
            user_input=1; %A value so that it enters the while loop below
            while ~isempty(user_input)
                str1='Next, you will set maximum values of distances between the blue and red arm markers';
                str2='First, to help make this decision, enter time point you want to visualize (or just press enter to continue) \n';
                user_input=input([str1 str2]);
                %Make sure the input was valid (an integer between start and finish)
                if ~isempty(user_input)
                    while ~(isnumeric(user_input) && mod(user_input,1)==0 && user_input>=start && user_input<=finish)
                        user_input=input('Re-enter valid time point \n');
                    end
                end
                if ~isempty(user_input)
                    figure;
                    plot_together_4colors_func(user_input, [7 8 10], [1:10], all_medians, color1, color2, color3, color4, start, finish, 1)
                end
            end
            
            % SET RED ARM TO BLUE ARM DISTANCES
            str1='Input red_elbow_dist_from_blue \n';
            str2='The blue values in the above plot should be generally be below this value (the red elbow should be within this distance of the blue arm)\n';
            str3='The purpose of this is to keep all points w/in this distance of the blue as marker candidates (useful if the red elbow marker was gone the previous frame) \n';
            str4='Value is generally ~ .05-.1 \n';
            red_elbow_dist_from_blue=input([str1 str2 str3 str4]);
            %Make sure it's a valid entry
            while ~(isnumeric(red_elbow_dist_from_blue))
                red_elbow_dist_from_blue=input('Re-enter valid value');
            end
            
            
            str1='Input red_blue_arm_dist_max \n';
            str2='All values in above plot should be below this value (Maximum distance from a red arm point to the blue)\n';
            str3='The purpose of this is to remove all points farther than this from the blue marker (to get rid of noise)\n';
            str4='Value is generally ~ .05-.1 \n';
            red_blue_arm_dist_max=input([str1 str2 str3 str4]);
            %Make sure it's a valid entry
            while ~(isnumeric(red_blue_arm_dist_max))
                red_blue_arm_dist_max=input('Re-enter valid value');
            end
            
        end
    end

    section_completed = 2.3;
    end
    %% Red Arm (Redo)
    %Note that this is different from the previous version of "Red Arm" because
    %now there are constraints involving distance from the blue arm marker
    if section_completed <2.4
    close all
    %Initializations
    plot_on=0;
    marker_ids=red_arm_marker_ids;
    color=color3;
    prev_meds=marker_inits(marker_ids,:);
    num_clust=length(marker_ids); %Number of clusters
    within_clust_dist1=.07; %How close points must be to the previous frame's first marker, # marker_ids(1), to be considered
    within_clust_dist2=.07; %How close points must be to the previous frame's second marker, # marker_ids(2), to be considered
    dist_min=0.05; %Minimum distance between markers (cluster medians aren't allowed w/ distance < min_dist)
    
    medians=NaN(num_clust,3,n_times); %Has NaNs when a marker is missing
    medians2=NaN(num_clust,3,n_times); %Has previous known positions when a marker is missing
    
    
    % LOOP THROUGH TIME
    t=0;
    prev_num_clust=num_clust;
    for i=start:finish
        
        t=t+1;
        
        %0. Get x,y,z positions
        [x,y,z] = getXYZfromKinect(color{i});
        loc=[x; y; z]';
        
        if ~isempty(loc)
            %1. Filter some bad points (those that are really far away)
            %Get distances of all points to the marker in the previous frame
            if t==1
                D=pdist2(loc,prev_meds);
            else
                D=pdist2(loc,medians2(:,:,t-1));
            end

            %Get distance to blue arm marker from the current frame
            D2=pdist2(loc,all_medians2(7,:,t));

            % Keep all the points close enough to either of the previous markers
            keep1=D(:,1)<within_clust_dist1;
            keep2=D(:,2)<within_clust_dist2;

            %Also keep if the it's near the blue arm marker (in case one of the
            %others disappears for a while)
            keep3=D2<red_elbow_dist_from_blue;

            %Remove points that are too far from the blue marker
            rmv0=D2>red_blue_arm_dist_max;

            %Remove points (those we're not keeping, or those we're removing)
            rmv=~(keep1 | keep2 | keep3) | rmv0;

            %Actually remove the points
            loc(rmv,:)=[];
        end
        
        %2. Cluster and assign
        [ prev_num_clust, prev_meds, medians, medians2  ] = cluster_func2(t, loc, num_clust, prev_num_clust, dist_min, prev_meds, medians, medians2, 1 );
        
        %3. Plot original image and cluster centers
        plot_clusts( plot_on, num_clust, x, y, z, medians, i, t, pause_time, xlims, ylims, zlims )
        
    end
    
    all_medians(marker_ids,:,:)=medians;
    all_medians2(marker_ids,:,:)=medians2;
    
    section_completed = 2.4;
    end
    
    %% Remove faulty red elbow points
    if section_completed < 2.5
    close all
    %This calculates (and plots) the angle made by points 7,8,10
    %Problems with the red elbow marker (point 10) will make this angle wrong
    %We will remove those points
    
    angle=NaN(1,n_times); %Initialize vector of angles for each frame
    
    for i=1:n_times
        
        if all(~isnan(all_medians([7 8 10],1,i))) %Only find angle for frames when all markers 7/8/10 are present
            a=all_medians(10,:,i);
            b=all_medians(7,:,i);
            c=all_medians2(8,:,i);
            
            u=a-b; %Vector from 10 to 7
            v=c-b; %Vector from 8 to 7
            
            angle(i)=acos(dot(u,v)/norm(u)/norm(v)); %Angle made by 10,7,8
        end
    end
    
    %Plot
    figure; plot(angle)
    red_elbow_angle_thresh=nanmean(angle)-4*nanstd(angle); %Frames with an angle below this will have marker 10 removed (default threshold)
    title(['Red Elbow Angles: Default Threshold=' num2str(red_elbow_angle_thresh)]);
    
    
    if ~use_defaults %Default was set above: nanmean(angle)-4*nanstd(angle). If you're not using the default:
        
        %VISUALIZE FRAMES
        user_input=1; %A value so that it enters the while loop below
        while ~isempty(user_input)
            str1='Next, you will enter a minimum threshold for the red elbow angle \n';
            str2='First, to decide how to set this threshold, you can enter a time point you want to visualize (or just press enter to continue) \n';
            user_input=input([str1 str2]);
            %Make sure the input was valid (an integer between start and finish)
            if ~isempty(user_input)
                while ~(isnumeric(user_input) && mod(user_input,1)==0 && user_input>=start && user_input<=finish)
                    user_input=input('Re-enter valid time point \n');
                    user_input = [];
                end
            end
            if ~isempty(user_input)
                figure
                plot_together_4colors_func(user_input, [7 8 10], [1:10], all_medians, color1, color2, color3, color4, start, finish, 1)
            end
            
        end
        
        %SET ANGLE THRESHOLD FOR RED ELBOW REMOVAL
        str1='Enter angle threshold for red elbow removal. Press enter for default. \n';
        temp=input(str1);
        %Make sure it's a valid entry
        while ~(isnumeric(temp) || isempty(temp))
            temp=input('Re-enter valid value');
        end
        
        if ~isempty(temp)
            red_elbow_angle_thresh=temp;
        end
        
    end
    
    %Remove red elbow points (based on angle)
    rmv10=angle<red_elbow_angle_thresh;
    all_medians(10,:,rmv10)=NaN;
    
    section_completed = 2.5;
    end
    
    %% Green Shoulder
    if section_completed <2.6
    close all
    if ~isempty(green_shoulder_marker_ids) %Only do this if it is a file with a green shoulder marker
        %Initializations
        plot_on=0;
        marker_ids=green_shoulder_marker_ids;
        color=color2;
        prev_meds=marker_inits(marker_ids,:);
        num_clust=length(marker_ids);
        within_clust_dist1=.07;
        dist_min=0.07;
        
        medians=NaN(num_clust,3,n_times);
        medians2=NaN(num_clust,3,n_times);
        
        
        % LOOP THROUGH TIME
        t=0;
        prev_num_clust=num_clust;
        for i=start:finish
            
            t=t+1;
            
            %0. Get x,y,z positions
            [x,y,z] = getXYZfromKinect(color{i});
            loc=[x; y; z]';
            
            if ~isempty(loc)
                %1. Filter some bad points (those that are really far away)
                if t==1
                    D=pdist2(loc,prev_meds);
                else
                    D=pdist2(loc,medians2(:,:,t-1));
                end

                % Keep all the points close enough to the previous marker
                keep1=D(:,1)<within_clust_dist1;

                % Remove
                rmv=~(keep1);
                loc(rmv,:)=[];
            end
            
            %2. Cluster and assign
            [ prev_num_clust, prev_meds, medians, medians2  ] = cluster_func2(t, loc, num_clust, prev_num_clust, dist_min, prev_meds, medians, medians2, 1 );
            
            %3. Plot original image and cluster centers
            plot_clusts( plot_on, num_clust, x, y, z, medians, i, t, pause_time, xlims, ylims, zlims )
            
        end
        
        all_medians(marker_ids,:,:)=medians;
        all_medians2(marker_ids,:,:)=medians2;
    end
    close all

    section_completed = 2.6;
    end
    %% Green Elbow
    if section_completed <2.7
    %Initializations
    plot_on=0;
    marker_ids=green_elbow_marker_ids;
    color=color2;
    prev_meds=marker_inits(marker_ids,:);
    num_clust=length(marker_ids);
    within_clust_dist1=.07;
    dist_min=0.07;
    
    medians=NaN(num_clust,3,n_times);
    medians2=NaN(num_clust,3,n_times);
    
    
    % LOOP THROUGH TIME
    t=0;
    prev_num_clust = num_clust;
    for i=start:finish
        
        t=t+1;
        
        %0. Get x,y,z positions
        [x,y,z] = getXYZfromKinect(color{i});
        loc=[x; y; z]';
        
        if ~isempty(loc)
            %1. Filter some bad points (those that are really far away)
            if t==1
                D=pdist2(loc,prev_meds);
                prev_num_clust=num_clust;
            else
                D=pdist2(loc,medians2(:,:,t-1));
            end

            % Keep all the points close enough to the previous marker
            keep1=D(:,1)<within_clust_dist1;

            %Also use distance from red elbow marker
            D2=pdist2(loc,all_medians(10,:,t));
            keep2=D2<.03; %Keep points that are close to red elbow marker
            rmv0=D2>.03; %Remove points that are too far from red elbow marker

            rmv=~(keep1|keep2) | rmv0; %Keep points that are either close enough to
            %the previous marker or the red elbow marker. Additionally, remove
            %points that are too far from the red elbow marker (even if they're
            %close enough to the previous marker)

            %Remove
            loc(rmv,:)=[];
        end
        
        %2. Cluster and assign
        [ prev_num_clust, prev_meds, medians, medians2  ] = cluster_func2(t, loc, num_clust, prev_num_clust, dist_min, prev_meds, medians, medians2, 1 );
        
        %3. Plot original image and cluster centers
        plot_clusts( plot_on, num_clust, x, y, z, medians, i, t, pause_time, xlims, ylims, zlims )
        
    end
    
    all_medians(marker_ids,:,:)=medians;
    all_medians2(marker_ids,:,:)=medians2;
    
    section_completed = 2.7;
    end
    %% Remove faulty green elbow points

    close all
    %This calculates (and plots) the angle made by points 7,8,6
    %Problems with the green elbow marker (point 6) will make this angle wrong
    %We will remove those points
    
    angle=NaN(1,n_times); %Initialize vector of angles for each frame
    
    for i=1:n_times
        
        if all(~isnan(all_medians([7 8 6],1,i))) %Only find angle for frames when all markers 6/7/8 are present
            
            a=all_medians(6,:,i);
            b=all_medians(7,:,i);
            c=all_medians2(8,:,i);
            
            u=a-b; %Vector from 6 to 7
            v=c-b; %Vector from 8 to 7
            
            angle(i)=acos(dot(u,v)/norm(u)/norm(v)); %Angle made by 6,7,8
        end
    end
    
    %Plot
    figure; plot(angle)
    green_elbow_angle_thresh=nanmean(angle)-4*nanstd(angle); %Frames with an angle below this will have marker 6 removed
    title(['Green Elbow Angles: Default Threshold=' num2str(green_elbow_angle_thresh)]);
    
    if ~use_defaults %Default was set above: nanmean(angle)-4*nanstd(angle). If you're not using the default:
        
        %VISUALIZE FRAMES
        user_input=1; %A value so that it enters the while loop below
        while ~isempty(user_input)
            str1='Next, you will enter a minimum threshold for the green elbow angle \n';
            str2='First, to decide how to set this threshold, you can enter a time point you want to visualize (or just press enter to continue) \n';
            user_input=input([str1 str2]);
            %Make sure the input was valid (an integer between start and finish)
            if ~isempty(user_input)
                while ~(isnumeric(user_input) && mod(user_input,1)==0 && user_input>=start && user_input<=finish)
                    user_input=input('Re-enter valid time point \n');
                end
            end
            if ~isempty(user_input)
                figure
                plot_together_4colors_func(user_input, [6 7 8], [1:10], all_medians, color1, color2, color3, color4, start, finish, 1)
            end
        end
        
        % SET ANGLE THRESHOLD FOR GREEN ELBOW REMOVAL
        str1='Enter angle threshold for green elbow removal. Press enter for default. \n';
        temp=input(str1);
        while ~(isnumeric(temp) || isempty(temp))
            temp=input('Re-enter valid value');
        end
        if ~isempty(temp)
            green_elbow_angle_thresh=temp;
        end
        
    end
    
    % Remove green elbow points (based on angle)
    rmv6=angle<green_elbow_angle_thresh;
    all_medians(6,:,rmv6)=NaN;

    %log file
    section_completed = 3;

end
%% 4. PRELIMINARY TRACKING OF HAND MARKERS (IN ORDER TO SET DISTANCE CONSTRAINTS TO ARM MARKERS)
if ~exist('section_completed','var') || section_completed<4
    close all
    %% Red Hand (Preliminary)
    if section_completed < 3.1
    if first_time %If this is not the first file from a date, we don't need to run this.
        
        %Initializations
        plot_on=0;
        marker_ids=red_hand_marker_ids;
        color=color3;
        prev_meds=marker_inits(marker_ids,:);
        num_clust=length(marker_ids);
        within_clust_dist1=.07;  %How close points must be to the previous frame's first marker, # marker_ids(1), to be considered
        dist_min=0.02;
        
        medians=NaN(num_clust,3,n_times);
        medians2=NaN(num_clust,3,n_times);
        
        
        % LOOP THROUGH TIME
        t=0;
        prev_num_clust = num_clust;
        for i=start:finish_prelim
            
            t=t+1;
            
            %0. Get x,y,z positions
            [x,y,z] = getXYZfromKinect(color{i});
            loc=[x; y; z]';
            
            if ~isempty(loc)
                %1. Filter some bad points (those that are really far away)
                %Get distances of all points to the marker in the previous frame
                if t==1
                    D=pdist2(loc,prev_meds);
                else
                    D=pdist2(loc,medians2(:,:,t-1));
                end

                % Keep all the points close enough to either of the previous markers
                keep1=D(:,1)<within_clust_dist1;

                %Remove points (those we're not keeping)
                rmv=~keep1;

                %Actually remove the points
                loc(rmv,:)=[];
            end
            
            %2. Cluster and assign
            %Note that this uses "cluster_func" instead of "cluster_func2"
            %which is slightly faster but less accurate. This is because we
            %will be redoing this later with cluster_func2. This current run is
            %only to determine the distances from the red hand markers to arm
            %markers (which will help in the next run)
            [ prev_num_clust, prev_meds, medians, medians2  ] = cluster_func(t, loc, num_clust, prev_num_clust, dist_min, .05, prev_meds, medians, medians2 );
            
            %3. Plot original image and cluster centers
            plot_clusts( plot_on, num_clust, x, y, z, medians, i, t, pause_time, xlims, ylims, zlims )
            
        end
        
        all_medians(marker_ids,:,:)=medians;
        all_medians2(marker_ids,:,:)=medians2;
        
    end
    
    section_completed = 3.1;
    end
    %% Yellow Hand (Preliminary)
    if section_completed <3.2
    close all
    if first_time %If this is not the first file from a date, we don't need to run this.
        
        %Initializations
        plot_on=0;
        marker_ids=yellow_hand_marker_ids;
        color=color4;
        prev_meds=marker_inits(marker_ids,:);
        num_clust=length(marker_ids);
        within_clust_dist1=.07;  %How close points must be to the previous frame's first marker, # marker_ids(1), to be considered
        dist_min=0.02;
        
        medians=NaN(num_clust,3,n_times);
        medians2=NaN(num_clust,3,n_times);
        
        
        % LOOP THROUGH TIME
        t=0;
        prev_num_clust = num_clust;
        for i=start:finish_prelim
            
            t=t+1;
            
            %0. Get x,y,z positions
            [x,y,z] = getXYZfromKinect(color{i});
            loc=[x; y; z]';
            
            if ~isempty(loc)
                %1. Filter some bad points (those that are really far away)
                %Get distances of all points to the marker in the previous frame
                if t==1
                    D=pdist2(loc,prev_meds);
                else
                    D=pdist2(loc,medians2(:,:,t-1));
                end

                % Keep all the points close enough to either of the previous markers
                keep1=D(:,1)<within_clust_dist1;

                %Remove points (those we're not keeping)
                rmv=~keep1;

                %Actually remove the points
                loc(rmv,:)=[];
            end
            
            %2. Cluster and assign
            %Note that this uses "cluster_func" instead of "cluster_func2"
            %which is slightly faster but less accurate. This is because we
            %will be redoing this later with cluster_func2. This current run is
            %only to determine the distances from the red hand markers to arm
            %markers (which will help in the next run)
            [ prev_num_clust, prev_meds, medians, medians2  ] = cluster_func(t, loc, num_clust, prev_num_clust, dist_min, .05, prev_meds, medians, medians2 );
            
            %3. Plot original image and cluster centers
            plot_clusts( plot_on, num_clust, x, y, z, medians, i, t, pause_time, xlims, ylims, zlims )
            
        end
        
        all_medians(marker_ids,:,:)=medians;
        all_medians2(marker_ids,:,:)=medians2;
        
    end
    
    section_completed = 3.2;
    end

    %% Green Hand (Preliminary)
    if section_completed <3.3
    close all
    if first_time %If this is not the first file from a date, we don't need to run this.
        
        %Initializations
        plot_on=0;
        marker_ids=green_hand_marker_ids;
        color=color2;
        prev_meds=marker_inits(marker_ids,:);
        num_clust=length(marker_ids);
        within_clust_dist1=.07; %How close points must be to the previous frame's first marker, # marker_ids(1), to be considered
        within_clust_dist2=.07; %How close points must be to the previous frame's second marker, # marker_ids(2), to be considered
        dist_min=0.03;
        
        medians=NaN(num_clust,3,n_times);
        medians2=NaN(num_clust,3,n_times);
        
        
        % LOOP THROUGH TIME
        t=0;
        prev_num_clust = num_clust;
        for i=start:finish_prelim
            
            t=t+1;
            
            %0. Get x,y,z positions
            [x,y,z] = getXYZfromKinect(color{i});
            loc=[x; y; z]';
            
            if ~isempty(loc)
                %1. Filter some bad points (those that are really far away)
                %Get distances of all points to the marker in the previous frame
                if t==1
                    D=pdist2(loc,prev_meds);
                else
                    D=pdist2(loc,medians2(:,:,t-1));
                end
                % Keep all the points close enough to either of the previous markers
                keep1=D(:,1)<within_clust_dist1;
                keep2=D(:,2)<within_clust_dist2;

                %Remove points (those we're not keeping)
                rmv=~(keep1 | keep2);

                %Actually remove the points
                loc(rmv,:)=[];
            end
            
            %2. Cluster and assign
            %Note that this uses "cluster_func" instead of "cluster_func2"
            %which is slightly faster but less accurate. This is because we
            %will be redoing this later with cluster_func2. This current run is
            %only to determine the distances from the green hand to arm
            %markers (which will help in the next run)
            [ prev_num_clust, prev_meds, medians, medians2  ] = cluster_func(t, loc, num_clust, prev_num_clust, dist_min, .05, prev_meds, medians, medians2 );
            
            %3. Plot original image and cluster centers
            plot_clusts( plot_on, num_clust, x, y, z, medians, i, t, pause_time, xlims, ylims, zlims )
            
        end
        
        all_medians(marker_ids,:,:)=medians;
        all_medians2(marker_ids,:,:)=medians2;
        
    end
    
    section_completed = 3.3;
    end
    
    %% Blue Hand (Preliminary)
    if section_completed < 4
    close all
    if first_time %If this is not the first file from a date, we don't need to run this.
        
        %Initializations
        plot_on=0;
        marker_ids=blue_hand_marker_ids;
        color=color1;
        prev_meds=marker_inits(marker_ids,:);
        num_clust=length(marker_ids);
        within_clust_dist1=.07;
        dist_min=0.07;
        
        medians=NaN(num_clust,3,n_times);
        medians2=NaN(num_clust,3,n_times);
        
        
        % LOOP THROUGH TIME
        t=0;
        prev_num_clust = num_clust;
        for i=start:finish_prelim
            
            t=t+1;
            
            %0. Get x,y,z positions
            [x,y,z] = getXYZfromKinect(color{i});
            loc=[x; y; z]';
            
            if ~isempty(loc)
                %1. Filter some bad points (those that are really far away)
                %Get distances of all points to the marker in the previous frame
                if t==1
                    D=pdist2(loc,prev_meds);
                else
                    D=pdist2(loc,medians2(:,:,t-1));
                end

                %Keep points close enough to previous marker
                keep1=D(:,1)<within_clust_dist1;
                rmv=~(keep1);

                %Actually remove
                loc(rmv,:)=[];
            end
            
            %2. Cluster and assign
            %Note that this uses "cluster_func" instead of "cluster_func2"
            %which is slightly faster but less accurate. This is because we
            %will be redoing this later with cluster_func2. This current run is
            %only to determine the distances from the blue hand to arm
            %markers (which will help in the next run)
            [ prev_num_clust, prev_meds, medians, medians2  ] = cluster_func(t, loc, num_clust, prev_num_clust, dist_min, .05, prev_meds, medians, medians2 );
            
            %3. Plot original image and cluster centers
            plot_clusts( plot_on, num_clust, x, y, z, medians, i, t, pause_time, xlims, ylims, zlims )
            
        end
        
        all_medians(marker_ids,:,:)=medians;
        all_medians2(marker_ids,:,:)=medians2;
    end

    %log file
    section_completed = 4;
    end
end

%% 5. SET DISTANCE CONSTRAINTS OF HAND MARKERS TO ARM MARKERS
if ~exist('section_completed','var') || section_completed<=5
    %% Set distance limits of hand markers to red elbow marker (after plotting the distances first)
    if section_completed <4.1
    close all
    %PLOT
    %Plots the distances of every hand marker to to red elbow marker in order
    %to determine what distances are allowed (for rerunning the hand marker
    %tracking)
    if first_time
        
        %Calculate distances
        for i=1:n_times_prelim
            dists1(i)=pdist2(all_medians(10,:,i),all_medians(1,:,i)); %Distance from point 10 (red elbow to point 1)
            dists2(i)=pdist2(all_medians(10,:,i),all_medians(2,:,i)); %etc...
            dists3(i)=pdist2(all_medians(10,:,i),all_medians(3,:,i));
            dists4(i)=pdist2(all_medians(10,:,i),all_medians(4,:,i));
            dists5(i)=pdist2(all_medians(10,:,i),all_medians(5,:,i));
        end
        
        %Plot
        figure; plot(dists1,'g'); hold on;
        plot(dists2,'b');
        plot(dists3,'r');
        plot(dists4,'y');
        plot(dists5,'g');
        title('Distance between red elbow marker (10) and hand markers');
        legend('10-1','10-2','10-3','10-4','10-5');
        
        
        if use_defaults %If you use the defaults
            
            str1='Enter vector of times to calculate default distances (e.g. 1:20000) \n';
            str2='Or just press enter to use all times \n';
            times_inc=input([str1 str2]);
            if isempty(times_inc)
                times_inc=1:n_times_prelim;
            end 
            
            %Get the distances at the times you include
            dists1=dists1(times_inc);
            dists2=dists2(times_inc);
            dists3=dists2(times_inc);
            dists4=dists2(times_inc);
            dists5=dists2(times_inc);
            
            green_hand_dists_elbow=[nanmean(dists5)-5*nanstd(dists5) nanmean(dists1)+5*nanstd(dists1)];
            red_hand_dists_elbow=[nanmean(dists3)-5*nanstd(dists3) nanmean(dists3)+5*nanstd(dists3)];
            blue_hand_dists_elbow=[nanmean(dists2)-5*nanstd(dists2) nanmean(dists2)+5*nanstd(dists2)];
            yellow_hand_dists_elbow=[nanmean(dists4)-5*nanstd(dists4) nanmean(dists4)+5*nanstd(dists4)];
            green_separator=(nanmean(dists5)+nanmean(dists1))/2; 
            
        else %If you don't use the defaults
            
      
            %Visualize Frames
            user_input=1; %A value so that it enters the while loop below
            while ~isempty(user_input)
                str1='Below you will enter limits for the distances between the red elbow marker and hand markers \n';
                str2='First, to help set these limits, you can enter a time point you want to visualize (or just press enter to continue) \n';
                user_input=input([str1 str2]);
                %Make sure the input was valid (an integer between start and finish)
                if ~isempty(user_input)
                    while ~(isnumeric(user_input) && mod(user_input,1)==0 && user_input>=start && user_input<=finish)
                        user_input=input('Re-enter valid time point \n');
                    end
                end
                if ~isempty(user_input)
                    figure
                    plot_together_4colors_func(user_input, [1:5], [1:10], all_medians, color1, color2, color3, color4, start, finish, 1)
                end
            end
            
            
            
            % Enter hand distance limits from red elbow
            
            str1='Input green_hand_dists_elbow \n';
            str2='Lower and upper limits of distances of the green hand markers to the red elbow marker\n';
            str3='Value is generally ~ [.15,.26] (around 2 or 3 cm from most points) \n';
            green_hand_dists_elbow=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(green_hand_dists_elbow)==2)
                green_hand_dists_elbow=input('Re-enter valid values');
            end
            
            str1='Input red_hand_dists_elbow \n';
            str2='Lower and upper limits of distances of the red hand markers to the red elbow marker\n';
            str3='Value is generally ~ [.17,.23] (around 2 or 3 cm from most points) \n';
            red_hand_dists_elbow=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(red_hand_dists_elbow)==2)
                red_hand_dists_elbow=input('Re-enter valid values');
            end
            
            str1='Input blue_hand_dists_elbow \n';
            str2='Lower and upper limits of distances of the blue hand markers to the red elbow marker\n';
            str3='Value is generally ~ [.17,.23] (around 2 or 3 cm from most points) \n';
            blue_hand_dists_elbow=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(blue_hand_dists_elbow)==2)
                blue_hand_dists_elbow=input('Re-enter valid values');
            end
            
            str1='Input yellow_hand_dists_elbow \n';
            str2='Lower and upper limits of distances of the yellow hand markers to the red elbow marker\n';
            str3='Value is generally ~ [.15,.21] (around 2 or 3 cm from most points) \n';
            yellow_hand_dists_elbow=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(yellow_hand_dists_elbow)==2)
                yellow_hand_dists_elbow=input('Re-enter valid values');
            end
            
            str1='Input green_separator \n';
            str2='Distance that separates the green hand points (marker 1 and 5) \n';
            str3='Value is generally ~ .2\n';
            green_separator=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(isnumeric(green_separator))
                green_separator=input('Re-enter valid values');
            end
            
        end
        
    end
    
    section_completed = 4.1;
    end

    %% Set distance limits of hand markers to blue arm marker (after plotting the distances first)
    if section_completed <4.2
    close all
    %PLOT
    %Plots the distances of every hand marker to to blue arm marker in order
    %to determine what distances are allowed (for rerunning the hand marker
    %tracking)
    
    %Note that using the distance from the hand to the blue arm marker only is helpful for a task with holding the handle
    
    if first_time
        
        %Calculate distances
        for i=1:n_times_prelim
            dists1(i)=pdist2(all_medians(7,:,i),all_medians(1,:,i)); %Distance from point 7 (blue arm) to point 1
            dists2(i)=pdist2(all_medians(7,:,i),all_medians(2,:,i));
            dists3(i)=pdist2(all_medians(7,:,i),all_medians(3,:,i));
            dists4(i)=pdist2(all_medians(7,:,i),all_medians(4,:,i));
            dists5(i)=pdist2(all_medians(7,:,i),all_medians(5,:,i));
        end
        
        
        if use_defaults %If you use the defaults
            
            %Get the distances at the times you include (specified when setting
            %distances to red elbow marker)
            dists1=dists1(times_inc);
            dists2=dists2(times_inc);
            dists3=dists2(times_inc);
            dists4=dists2(times_inc);
            dists5=dists2(times_inc);
            
            green_hand_dists_bluearm=[nanmean(dists5)-6*nanstd(dists5) nanmean(dists1)+6*nanstd(dists1)];
            red_hand_dists_bluearm=[nanmean(dists3)-6*nanstd(dists3) nanmean(dists3)+6*nanstd(dists3)];
            blue_hand_dists_bluearm=[nanmean(dists2)-6*nanstd(dists2) nanmean(dists2)+6*nanstd(dists2)];
            yellow_hand_dists_bluearm=[nanmean(dists4)-6*nanstd(dists4) nanmean(dists4)+6*nanstd(dists4)];
            
        else %If you don't use the defaults
            
            
            %Plot
            figure; %Yellow
            plot(dists4,'y-x');
            title('Distance from blue arm marker to yellow hand marker');
            figure; %Blue
            plot(dists2,'b-x');
            title('Distance from blue arm marker to blue hand marker');
            figure; %Red
            plot(dists3,'r-x');
            title('Distance from blue arm marker to red hand marker');
            figure; %Green
            plot(dists1,'g-x');
            hold on;
            plot(dists5,'c-x');
            title('Distance from blue arm marker to green hand markers');
            legend('Dist to pt1','Dist to pt5');
            
            
            
            % Enter hand distance limits from blue arm
            
            str1='Input green_hand_dists_bluearm \n';
            str2='Lower and upper limits of distances of the green hand markers (green and cyan above) to the blue arm marker\n';
            str3='Value is generally ~ [.15,.30] (around 4 cm from most points) \n';
            green_hand_dists_bluearm=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(green_hand_dists_bluearm)==2)
                green_hand_dists_bluearm=input('Re-enter valid values');
            end
            
            str1='Input red_hand_dists_bluearm \n';
            str2='Lower and upper limits of distances of the red hand markers (red above) to the blue arm marker\n';
            str3='Value is generally ~ [.16,.28] (around 4 cm from most points) \n';
            red_hand_dists_bluearm=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(red_hand_dists_bluearm)==2)
                red_hand_dists_bluearm=input('Re-enter valid values');
            end
            
            str1='Input blue_hand_dists_bluearm \n';
            str2='Lower and upper limits of distances of the blue hand markers (blue above) to the blue arm marker\n';
            str3='Value is generally ~ [.16,.28] (around 4 cm from most points) \n';
            blue_hand_dists_bluearm=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(blue_hand_dists_bluearm)==2)
                blue_hand_dists_bluearm=input('Re-enter valid values');
            end
            
            str1='Input yellow_hand_dists_bluearm \n';
            str2='Lower and upper limits of distances of the yellow hand markers (yellow above) to the blue arm marker\n';
            str3='Value is generally ~ [.14,.26] (around 4 cm from most points) \n';
            yellow_hand_dists_bluearm=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(yellow_hand_dists_bluearm)==2)
                yellow_hand_dists_bluearm=input('Re-enter valid values');
            end
            
        end
    end
    
    section_completed = 4.2;
    end
    %% Set distance limits of hand markers to red arm marker (after plotting the distances first)
    
    %Plots the distances of every hand marker to to red arm marker in order
    %to determine what distances are allowed (for rerunning the hand marker
    %tracking)
    
    %Note that using the distance from the hand to the red arm marker only is helpful for a task with holding the handle
    if section_completed <4.3
    close all
    if first_time
        %Calculate distances
        for i=1:n_times_prelim
            dists1(i)=pdist2(all_medians(8,:,i),all_medians(1,:,i)); %Distance from point 8 (red arm to point 1)
            dists2(i)=pdist2(all_medians(8,:,i),all_medians(2,:,i));
            dists3(i)=pdist2(all_medians(8,:,i),all_medians(3,:,i));
            dists4(i)=pdist2(all_medians(8,:,i),all_medians(4,:,i));
            dists5(i)=pdist2(all_medians(8,:,i),all_medians(5,:,i));
        end
        
        
        if use_defaults %If you use the defaults
            
            %Get the distances at the times you include (specified when setting
            %distances to red elbow marker)
            dists1=dists1(times_inc);
            dists2=dists2(times_inc);
            dists3=dists2(times_inc);
            dists4=dists2(times_inc);
            dists5=dists2(times_inc);
            
            green_hand_dists_redarm=[nanmean(dists5)-6*nanstd(dists5) nanmean(dists1)+6*nanstd(dists1)];
            red_hand_dists_redarm=[nanmean(dists3)-6*nanstd(dists3) nanmean(dists3)+6*nanstd(dists3)];
            blue_hand_dists_redarm=[nanmean(dists2)-6*nanstd(dists2) nanmean(dists2)+6*nanstd(dists2)];
            yellow_hand_dists_redarm=[nanmean(dists4)-6*nanstd(dists4) nanmean(dists4)+6*nanstd(dists4)];
            
        else %If you don't use the defaults
            
            
            %Plot
            figure; %Yellow
            plot(dists4,'y-x');
            title('Distance from red arm marker to yellow hand markers');
            figure; %Blue
            plot(dists2,'b-x');
            title('Distance from red arm marker to blue hand markers');
            figure; %Red
            plot(dists3,'r-x');
            title('Distance from red arm marker to red hand markers');
            figure; %Green
            plot(dists1,'g-x');
            hold on;
            plot(dists5,'c-x');
            title('Distance from red arm marker to green hand markers');
            legend('Dist to pt1','Dist to pt5');
            
            
            
            % Enter hand distance limits from red arm
            
            str1='Input green_hand_dists_redarm \n';
            str2='Lower and upper limits of distances of the green hand markers (green and cyan above) to the red arm marker\n';
            str3='Value is generally ~ [.15,.35] (around 5 cm from most points) \n';
            green_hand_dists_redarm=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(green_hand_dists_redarm)==2)
                green_hand_dists_redarm=input('Re-enter valid values');
            end
            
            str1='Input red_hand_dists_redarm \n';
            str2='Lower and upper limits of distances of the red hand markers (red above) to the red arm marker\n';
            str3='Value is generally ~ [.15,.34] (around 5 cm from most points) \n';
            red_hand_dists_redarm=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(red_hand_dists_redarm)==2)
                red_hand_dists_redarm=input('Re-enter valid values');
            end
            
            str1='Input blue_hand_dists_redarm \n';
            str2='Lower and upper limits of distances of the blue hand markers (blue above) to the red arm marker\n';
            str3='Value is generally ~ [.15,.34] (around 5 cm from most points) \n';
            blue_hand_dists_redarm=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(blue_hand_dists_redarm)==2)
                blue_hand_dists_redarm=input('Re-enter valid values');
            end
            
            str1='Input yellow_hand_dists_redarm \n';
            str2='Lower and upper limits of distances of the yellow hand markers (yellow above) to the red arm marker\n';
            str3='Value is generally ~ [.15,.34] (around 5 cm from most points) \n';
            yellow_hand_dists_redarm=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(yellow_hand_dists_redarm)==2)
                yellow_hand_dists_redarm=input('Re-enter valid values');
            end
            
        end
    end
    
    section_completed = 4.3;
    end
    %% Set distance limits between green hand markers
    if section_completed <4.4
    close all
    %Plots the distances of the green hand markers to each other, in order to
    %determine what distances are allowed (for rerunning the hand marker tracking)
    
    if first_time
        %Calculate distances
        for i=1:n_times_prelim
            dists1(i)=pdist2(all_medians(5,:,i),all_medians(1,:,i)); %Distances between green hand markers
        end
        
        
        if use_defaults %If you use the defaults
            
            %Get the distances at the times you include (specified when setting
            %distances to red elbow marker)
            dists1=dists1(times_inc);
            
            green_dist_min=nanmean(dists1)-5*nanstd(dists1);
            
            if green_dist_min<.02 %Should never be less than this value
                green_dist_min=.02;
            end
            
        else %If you don't use the defaults
            
            
            
            %Plot
            figure; plot(dists1,'g');
            title('Distance between green hand markers');
            
            
            % Enter minimum hand distances from each other
            
            str1='Input green_dist_min \n';
            str2='Minimum distance allowed between green hand markers (green above)\n';
            str3='Value is generally ~ .03 \n';
            green_dist_min=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(isnumeric(green_dist_min))
                green_dist_min=input('Re-enter valid values');
            end
            
        end
        
    end
    end
    %log file
    section_completed = 5;
end

%% 6. TRACK HAND MARKERS (USING DISTANCE CONSTRAINTS FROM ABOVE), EXCEPT YELLOW
if ~exist('section_completed','var') || section_completed<=6
    if section_completed < 5.1
    %% Green Hand (Redo)
    close all
    %Initializations
    plot_on=0;
    marker_ids=green_hand_marker_ids;
    color=color2;
    prev_meds=marker_inits(marker_ids,:);
    num_clust=length(marker_ids); %Number of clusters
    within_clust_dist1=.07;%How close points must be to the previous frame's first marker, # marker_ids(1), to be considered
    within_clust_dist2=.07; %How close points must be to the previous frame's second marker, # marker_ids(2), to be considered
    dist_min=green_dist_min; %Minimum distance between markers (cluster medians aren't allowed w/ distance < min_dist)
    
    medians=NaN(num_clust,3,n_times); %Has NaNs when a marker is missing
    medians2=NaN(num_clust,3,n_times); %Has previous known positions when a marker is missing
    
    num_gone1=0;%The number of frames the first marker has been gone
    num_gone2=0; %The number of frames the second marker has been gone
    
    % LOOP THROUGH TIME
    t=0;
    prev_num_clust = num_clust;
    for i=start:finish
        
        t=t+1;
        
        %0. Get x,y,z positions
        [x,y,z] = getXYZfromKinect(color{i});
        loc=[x; y; z]';
        
        if ~isempty(loc)
            %1. Filter some bad points (those that are really far away)
            %Get distances of all points to the marker in the previous frame
            if t==1
                D=pdist2(loc,prev_meds);
            else
                D=pdist2(loc,medians2(:,:,t-1));
            end

            % Keep all the points close enough to either of the previous markers
            keep1=D(:,1)<within_clust_dist1;
            keep2=D(:,2)<within_clust_dist2;

            %Remove points that are too close or far from the red elbow marker
            D2=pdist2(loc,all_medians(10,:,t));
            rmv0=D2<green_hand_dists_elbow(1) | D2>green_hand_dists_elbow(2);

            %Remove points that are too close or far from the blue arm marker
            D3=pdist2(loc,all_medians(7,:,t));
            rmv1=D3<green_hand_dists_bluearm(1) | D3>green_hand_dists_bluearm(2);

            %Remove points that are too close or far from the red arm marker
            D4=pdist2(loc,all_medians(8,:,t));
            rmv2=D4<green_hand_dists_redarm(1) | D4>green_hand_dists_redarm(2);

            %Use above criteria to set points for removal
            %We will always remove points that are too close or far from the arm markers (rmv0, rmv1, rmv2).
            %Depending on how many frames the markers have been missing, we additionally use different criteria for removing.

            %If both markers have been missing for <=4 frames, keep points close
            %enough to the marker's locations in the previous frame
            if num_gone1<=4 && num_gone2<=4
                rmv=~(keep1 | keep2) | rmv0 | rmv1 | rmv2;
                %If the second marker has been missing for >4 frames, only keep points close
                %enough to the first marker's location in the previous frame
            else
                if num_gone1<=4 && num_gone2>4
                    rmv=~(keep1) | rmv0 | rmv1 | rmv2;
                    %If the first marker has been missing for >4 frames, only keep points close
                    %enough to the second marker's location in the previous frame
                else
                    if num_gone1>4 && num_gone2<=4
                        rmv=~(keep2) | rmv0 | rmv1 | rmv2;
                        %If both markers have been missing for >4 frames, don't keep any points
                        %based on distance to the markers' locations in the previous frame
                    else
                        rmv=rmv0 | rmv1 | rmv2;
                    end
                end
            end

            %Actually remove
            loc(rmv,:)=[];
        end
        
        %2. Cluster and assign
        [ prev_num_clust, prev_meds, medians, medians2  ] = cluster_func2(t, loc, num_clust, prev_num_clust, dist_min, prev_meds, medians, medians2 );
        
        %Update how many frames markers have been missing
        %If marker1 is missing, add 1 to num_gone1. Otherwise set num_gone1=0
        %(since it's been missing 0 frames)
        if isnan(medians(1,1,t))
            num_gone1=num_gone1+1;
        else
            num_gone1=0;
        end
        %If marker2 is missing, add 1 to num_gone2. Otherwise set num_gone2=0
        %(since it's been missing 0 frames)
        if isnan(medians(2,1,t))
            num_gone2=num_gone2+1;
        else
            num_gone2=0;
        end
        
        %If the red elbow marker is not missing, make sure the the first marker
        %(marker # 1) is farther from the red elbow marker than the second
        %marker (marker #5). If not, switch their assignment.
        %If the red elbow marker is missing, but the blue arm marker is not
        %missing, then do the same as above w/ the blue arm marker.
        if t>1
            %     if isnan(medians(1,1,t-1)) || isnan(medians(2,1,t-1))
            if ~isnan(all_medians(10,1,t))
                if pdist2(medians(1,:,t),all_medians(10,:,t))<pdist2(medians(2,:,t),all_medians(10,:,t))
                    temp=medians(1,:,t);
                    temp2=medians2(1,:,t);
                    medians(1,:,t)=medians(2,:,t);
                    medians(2,:,t)=temp;
                    medians2(1,:,t)=medians2(2,:,t);
                    medians2(2,:,t)=temp2;
                end
            else
                if ~isnan(all_medians(7,1,t))
                    if pdist2(medians(1,:,t),all_medians(7,:,t))<pdist2(medians(2,:,t),all_medians(7,:,t))
                        temp=medians(1,:,t);
                        temp2=medians2(1,:,t);
                        medians(1,:,t)=medians(2,:,t);
                        medians(2,:,t)=temp;
                        medians2(1,:,t)=medians2(2,:,t);
                        medians2(2,:,t)=temp2;
                    end
                end
            end
            %     end
            
            %If both markers were gone previous frame, and now there's one, assume
            %it's not the first marker (marker #1  by the fingers)
            if isnan(medians(1,1,t-1)) && isnan(medians(2,1,t-1))
                if ~isnan(medians(1,1,t)) && isnan(medians(2,1,t)) %If only the first marker shows up, then flip the assignment
                    temp=medians(1,:,t);
                    medians(1,:,t)=medians(2,:,t);
                    medians(2,:,t)=temp;
                end
            end
            
            %If the markers are too far away from the markers in the prevoius
            %frame, remove them.
            %For the first marker
            if abs(pdist2(medians(1,:,t),medians(1,:,t-1)))>within_clust_dist1
                medians(1,:,t)=NaN;
                medians2(1,:,t)=medians2(1,:,t-1);
            end
            %For the second marker
            if abs(pdist2(medians(2,:,t),medians(2,:,t-1)))>within_clust_dist2
                medians(2,:,t)=NaN;
                medians2(2,:,t)=medians2(2,:,t-1);
            end
            
            
            %If there's only a single marker (one is missing this frame),
            %determine its label based on the distance from the red elbow
            
            %The distance from the second marker (marker #5) to the red elbow
            %should be less than "green_separator." If it's more, then
            %change the label of this marker to the first marker (marker #1).
            if isnan(medians(1,1,t)) && ~isnan(medians(2,1,t))
                if pdist2(medians(2,:,t),all_medians(10,:,t))>green_separator
                    medians(1,:,t)=medians(2,:,t);
                    medians(2,:,t)=NaN;
                end
            end
            %The distance from the first marker (marker #1) to the red elbow
            %should be greater than "green_separator." If it's less, then
            %change the label of this marker to the second marker (marker #5).
            if ~isnan(medians(1,1,t)) && isnan(medians(2,1,t))
                if pdist2(medians(1,:,t),all_medians(10,:,t))<green_separator
                    medians(2,:,t)=medians(1,:,t);
                    medians(1,:,t)=NaN;
                end
            end
            
            
        end
        %3. Plot original image and cluster centers
        plot_clusts( plot_on, num_clust, x, y, z, medians, i, t, pause_time, xlims, ylims, zlims )
        
    end
    
    all_medians(marker_ids,:,:)=medians;
    all_medians2(marker_ids,:,:)=medians2;
    
    section_completed = 5.1;
    end
    %% Blue Hand (Redo)
    if section_completed <5.2
    close all
    %Initializations
    plot_on=0;
    marker_ids=blue_hand_marker_ids;
    color=color1;
    prev_meds=marker_inits(marker_ids,:);
    num_clust=length(marker_ids);
    within_clust_dist1=.07;
    dist_min=0.07;
    
    medians=NaN(num_clust,3,n_times);
    medians2=NaN(num_clust,3,n_times);
    
    num_gone=0; %The number of frames the marker has been gone
    
    % LOOP THROUGH TIME
    t=0;
    prev_num_clust = num_clust;
    for i=start:finish
        
        t=t+1;
        
        %0. Get x,y,z positions
        [x,y,z] = getXYZfromKinect(color{i});
        loc=[x; y; z]';
        
        if ~isempty(loc)
            %1. Filter some bad points (those that are really far away)
            %Get distances of all points to the marker in the previous frame
            if t==1
                D=pdist2(loc,prev_meds);
            else
                D=pdist2(loc,medians2(:,:,t-1));
            end

            % Keep all the points close enough to the previous marker
            keep1=D(:,1)<within_clust_dist1;

            %Remove points that are too close or far from the red elbow marker
            D2=pdist2(loc,all_medians(10,:,t));
            rmv0=D2<blue_hand_dists_elbow(1) | D2>blue_hand_dists_elbow(2);

            %Remove points that are too close or far from the blue arm marker
            D3=pdist2(loc,all_medians(7,:,t));
            rmv1=D3<blue_hand_dists_bluearm(1) | D3>blue_hand_dists_bluearm(2);

            %Remove points that are too close or far from the red arm marker
            D4=pdist2(loc,all_medians(8,:,t));
            rmv2=D4<blue_hand_dists_redarm(1) | D4>blue_hand_dists_redarm(2);

            %Use above criteria to set points for removal
            %We will always remove points that are too close or far from the arm markers (rmv0, rmv1, rmv2).
            %If the marker has been missing for <=4 frames, keep points close
            %enough to the marker's location in the previous frame
            if num_gone<=4
                rmv=~(keep1)| rmv0 | rmv1 | rmv2;
            else
                %If the marker has been missing for >4 frames, don't keep any points
                %based on distance to the marker's location in the previous frame
                rmv=rmv0 | rmv1 | rmv2;
            end

            %Actually remove
            loc(rmv,:)=[];
        end
        
        %2. Cluster and assign
        [ prev_num_clust, prev_meds, medians, medians2  ] = cluster_func2(t, loc, num_clust, prev_num_clust, dist_min, prev_meds, medians, medians2 );
        
        
        %Update how many frames markers have been missing
        %If the marker is missing, add 1 to num_gone. Otherwise set num_gone=0
        %(since it's been missing 0 frames)
        if isnan(medians(1,1,t))
            num_gone=num_gone+1;
        else
            num_gone=0;
        end
        
        
        %3. Plot original image and cluster centers
        plot_clusts( plot_on, num_clust, x, y, z, medians, i, t, pause_time, xlims, ylims, zlims )
        
    end
    
    all_medians(marker_ids,:,:)=medians;
    all_medians2(marker_ids,:,:)=medians2;
    
    section_completed = 5.2;
    end
    %% Red Hand (Redo)
    if section_completed <5.3
    close all
    %Initializations
    plot_on=0;
    marker_ids=red_hand_marker_ids;
    color=color3;
    prev_meds=marker_inits(marker_ids,:);
    num_clust=length(marker_ids);
    within_clust_dist1=.07;
    dist_min=0.07;
    
    medians=NaN(num_clust,3,n_times);
    medians2=NaN(num_clust,3,n_times);
    
    num_gone=0; %The number of frames the marker has been gone
    
    % LOOP THROUGH TIME
    t=0;
    prev_num_clust = num_clust;
    for i=start:finish
        
        t=t+1;
        
        %0. Get x,y,z positions
        [x,y,z] = getXYZfromKinect(color{i});
        loc=[x; y; z]';
        
        if ~isempty(loc)
            %1. Filter some bad points (those that are really far away)
            %Get distances of all points to the marker in the previous frame
            if t==1
                D=pdist2(loc,prev_meds);
            else
                D=pdist2(loc,medians2(:,:,t-1));
            end

            % Keep all the points close enough to the previous marker
            keep1=D(:,1)<within_clust_dist1;

            %Remove points that are too close or far from the red elbow marker
            D2=pdist2(loc,all_medians(10,:,t));
            rmv0=D2<red_hand_dists_elbow(1) | D2>red_hand_dists_elbow(2);

            %Remove points that are too close or far from the blue arm marker
            D3=pdist2(loc,all_medians(7,:,t));
            rmv1=D3<red_hand_dists_bluearm(1) | D3>red_hand_dists_bluearm(2);

            %Remove points that are too close or far from the red arm marker
            D4=pdist2(loc,all_medians(8,:,t));
            rmv2=D4<red_hand_dists_redarm(1) | D4>red_hand_dists_redarm(2);

            %Use above criteria to set points for removal
            %We will always remove points that are too close or far from the arm markers (rmv0, rmv1, rmv2).
            %If the marker has been missing for <=4 frames, keep points close
            %enough to the marker's location in the previous frame
            if num_gone<=4
                rmv=~(keep1)| rmv0 | rmv1 | rmv2;
            else
                %If the marker has been missing for >4 frames, don't keep any points
                %based on distance to the marker's location in the previous frame
                rmv=rmv0 | rmv1 | rmv2;
            end

            %Actually remove
            loc(rmv,:)=[];
        end
        
        %2. Cluster and assign
        [ prev_num_clust, prev_meds, medians, medians2  ] = cluster_func2(t, loc, num_clust, prev_num_clust, dist_min, prev_meds, medians, medians2 );
        
        
        %Update how many frames markers have been missing
        %If the marker is missing, add 1 to num_gone. Otherwise set num_gone=0
        %(since it's been missing 0 frames)
        if isnan(medians(1,1,t))
            num_gone=num_gone+1;
        else
            num_gone=0;
        end
        
        
        %3. Plot original image and cluster centers
        plot_clusts( plot_on, num_clust, x, y, z, medians, i, t, pause_time, xlims, ylims, zlims )
        
    end
    
    all_medians(marker_ids,:,:)=medians;
    all_medians2(marker_ids,:,:)=medians2;

    %log file
    section_completed = 6;
    end
end

%% 7. MANUAL CORRECTION OF HAND MARKERS (REMOVING/SWITCHING) FOR FRAMES THAT GET AUTOMATICALLY FLAGGED
if ~exist('section_completed','var') || section_completed<=7
    %% Calculate hand distances from red elbow marker
    if section_completed <6.1
    close all
    %Initialize some vectors that I use later for calculating the distance
    %between points
    dists1=NaN(1,n_times);
    dists2=NaN(1,n_times);
    dists3=NaN(1,n_times);
    dists4=NaN(1,n_times);
    dists5=NaN(1,n_times);
    
    %Calculate distances from red elbow to points on the hand
    for i=1:n_times
        dists1(i)=pdist2(all_medians(10,:,i),all_medians(1,:,i));
        dists2(i)=pdist2(all_medians(10,:,i),all_medians(2,:,i));
        dists3(i)=pdist2(all_medians(10,:,i),all_medians(3,:,i));
        dists4(i)=pdist2(all_medians(10,:,i),all_medians(4,:,i));
        dists5(i)=pdist2(all_medians(10,:,i),all_medians(5,:,i));
    end
    
    %Plot
    % figure;
    % plot(dists1,'g-x');
    % hold on;
    % plot(dists2,'b-x');
    % plot(dists3,'r-x');
    % plot(dists4,'m-x');
    % plot(dists5,'c-x');
    
    section_completed = 6.1;
    end
    %% Make corrections when the green hand markers have a similar distance to the elbow
    
    %Find times when marker 1 and marker 5 are a similar distance to the elbow
    %marker (which is a problem)
    if section_completed <6.2
    idxs=find(abs(dists1-dists5)<.01);
    close all
    %Plot those times
    
    for i=1:length(idxs)
        figure(1)
        clf;
        plot_together_4colors_func(idxs(i), [1 5], [1:10], all_medians, color1, color2, color3, color4, start, finish, 1)
        title(num2str(idxs(i)));
        
        disp(['Correction block 1 of 5, correction ' num2str(i) ' out of ' num2str(length(idxs))])
        
        %Points to Remove
        str1='Pt 5 is a similar distance from elbow as Pt 1 \n';
        str2='Type in the points to remove \n';
        str3='e.g. 1, or [1,2] - Note that enter removes no points \n';
        rmv=input([str1 str2 str3]);
        %Make sure entry is valid (either empty, or composed of markers)
        while ~(isempty(rmv) || (all(mod(rmv,1)==0) && all(rmv>0) && all(rmv<=size(all_medians,1))))
            rmv=input('Enter valid point(s)');
        end
        for j=1:length(rmv)
            all_medians(rmv(j),:,idxs(i))=NaN;
        end
        
        %Points to Switch
        str2='Type in the points to switch \n';
        str3='e.g. [3,4], or [3,4; 5,6] - Note that enter switches no points \n';
        switches=input([str2 str3]);
        %Make sure entry is valid (either empty, or composed of markers)
        while ~(isempty(switches) || (all(all(mod(switches,1)==0)) && all(all(switches>0)) && all(all(switches<=size(all_medians,1)))))
            switches=input('Enter valid point(s)');
        end
        for j=1:size(switches,1)
            [ all_medians, all_medians2 ] = switch_pts(switches(j,:),idxs(i),all_medians,all_medians2);
        end
    end
    
    %Recalculate distances from red elbow to points on the hand (due to above changes)
    if ~isempty(idxs) %Only redo if there was a change above
        for i=1:n_times
            dists1(i)=pdist2(all_medians(10,:,i),all_medians(1,:,i));
            dists2(i)=pdist2(all_medians(10,:,i),all_medians(2,:,i));
            dists3(i)=pdist2(all_medians(10,:,i),all_medians(3,:,i));
            dists4(i)=pdist2(all_medians(10,:,i),all_medians(4,:,i));
            dists5(i)=pdist2(all_medians(10,:,i),all_medians(5,:,i));
        end
    end
    
    section_completed = 6.2;
    end
    %% Make corrections when marker 3 has a larger distance to the elbow than marker 1
    if section_completed < 6.3
    close all
    %Find times (idxs) where the distance from the elbow to point 3 are
    %greater than the distance from the elbow to point 1 (which shouldn't
    %happen)
    idxs=find(dists3>dists1);
    
    %Plot those times
    for i=1:length(idxs)
        figure(1)
        clf
        plot_together_4colors_func(idxs(i), [1 3 5], [1:10], all_medians, color1, color2, color3, color4, start, finish, 1)
        title(num2str(idxs(i)));
        
        disp(['Correction block 2 of 5, correction ' num2str(i) ' out of ' num2str(length(idxs))])
        
        %Points to Remove
        str1='Pt 3 is farther from elbow than Pt 1 \n';
        str2='Type in the points to remove \n';
        str3='e.g. 1, or [1,2] - Note that enter removes no points \n';
        rmv=input([str1 str2 str3]);
        %Make sure entry is valid (either empty, or composed of markers)
        while ~(isempty(rmv) || (all(mod(rmv,1)==0) && all(rmv>0) && all(rmv<=size(all_medians,1))))
            rmv=input('Enter valid point(s)');
        end
        for j=1:length(rmv)
            all_medians(rmv(j),:,idxs(i))=NaN;
        end
        
        %Points to Switch
        str2='Type in the points to switch \n';
        str3='e.g. [3,4], or [3,4; 5,6] - Note that enter switches no points \n';
        switches=input([str2 str3]);
        %Make sure entry is valid (either empty, or composed of markers)
        while ~(isempty(switches) || (all(all(mod(switches,1)==0)) && all(all(switches>0)) && all(all(switches<=size(all_medians,1)))))
            switches=input('Enter valid point(s)');
        end
        for j=1:size(switches,1)
            [ all_medians, all_medians2 ] = switch_pts(switches(j,:),idxs(i),all_medians,all_medians2);
        end
    end
    
    
    % Recalculate distances from red elbow to points on the hand (due to above changes)
    if ~isempty(idxs) %Only redo if there was a change above
        for i=1:n_times
            dists1(i)=pdist2(all_medians(10,:,i),all_medians(1,:,i));
            dists2(i)=pdist2(all_medians(10,:,i),all_medians(2,:,i));
            dists3(i)=pdist2(all_medians(10,:,i),all_medians(3,:,i));
            dists4(i)=pdist2(all_medians(10,:,i),all_medians(4,:,i));
            dists5(i)=pdist2(all_medians(10,:,i),all_medians(5,:,i));
        end
    end
    
    section_completed = 6.3;
    end
    
    %% Make corrections when marker 2 has a larger distance to the elbow than marker 1
    if section_completed < 6.4
    close all
    %Find times (idxs) where the distance from the elbow to point 2 are
    %greater than the distance from the elbow to point 1 (which shouldn't
    %happen)
    idxs=find(dists2>dists1);
    xWin = [-.04,.03];
    yWin = [0,.06];
    zWin = [.55,.58];
    indices = 1:45749;
    % color1 = removeWindow(prevColor1, indices, xWin, yWin,zWin);
    %Plot those times
    for i=1:length(idxs)
        figure(1)
        clf
        plot_together_4colors_func(idxs(i), [1 2 5], [1:10], all_medians, color1, color2, color3, color4, start, finish, 1)
        title(num2str(idxs(i)));
        
        disp(['Correction block 3 of 5, correction ' num2str(i) ' out of ' num2str(length(idxs))])
        
        %Points to Remove
        str1='Pt 2 is farther from elbow than Pt 1 \n';
        str2='Type in the points to remove \n';
        str3='e.g. 1, or [1,2] - Note that enter removes no points \n';
        rmv=input([str1 str2 str3]);
        %Make sure entry is valid (either empty, or composed of markers)
        while ~(isempty(rmv) || (all(mod(rmv,1)==0) && all(rmv>0) && all(rmv<=size(all_medians,1))))
            rmv=input('Enter valid point(s)');
        end
        for j=1:length(rmv)
            all_medians(rmv(j),:,idxs(i))=NaN;
        end
        
        %Points to Switch
        str2='Type in the points to switch \n';
        str3='e.g. [3,4], or [3,4; 5,6] - Note that enter switches no points \n';
        switches=input([str2 str3]);
        %Make sure entry is valid (either empty, or composed of markers)
        while ~(isempty(switches) || (all(all(mod(switches,1)==0)) && all(all(switches>0)) && all(all(switches<=size(all_medians,1)))))
            switches=input('Enter valid point(s)');
        end
        for j=1:size(switches,1)
            [ all_medians, all_medians2 ] = switch_pts(switches(j,:),idxs(i),all_medians,all_medians2);
        end
    end
    
    % Recalculate distances from red elbow to points on the hand (due to above changes)
    if ~isempty(idxs) %Only redo if there was a change above
        for i=1:n_times
            dists1(i)=pdist2(all_medians(10,:,i),all_medians(1,:,i));
            dists2(i)=pdist2(all_medians(10,:,i),all_medians(2,:,i));
            dists3(i)=pdist2(all_medians(10,:,i),all_medians(3,:,i));
            dists4(i)=pdist2(all_medians(10,:,i),all_medians(4,:,i));
            dists5(i)=pdist2(all_medians(10,:,i),all_medians(5,:,i));
        end
    end
    
    section_completed = 6.4;
    end
    %% Make corrections when marker 5 has a larger distance to the elbow than marker 3
    if section_completed <6.5
    close all
    
    %Find times when marker 5 has a greater distance to the elbow
    %than marker 3 (which is a problem)
    idxs=find(dists3-dists5<0.01);
    
    %Plot those times
    for i=1:length(idxs)
        figure(1)
        clf
        plot_together_4colors_func(idxs(i), [1 3 5], [1:10], all_medians, color1, color2, color3, color4, start, finish, 1)
        title(num2str(idxs(i)));
        
        disp(['Correction block 4 of 5, correction ' num2str(i) ' out of ' num2str(length(idxs))])
        
        %Points to Remove
        str1='Pt 5 is farther from elbow than Pt 3 or is too close to Pt 3\n';
        str2='Type in the points to remove \n';
        str3='e.g. 1, or [1,2] - Note that enter removes no points \n';
        rmv=input([str1 str2 str3]);
        %Make sure entry is valid (either empty, or composed of markers)
        while ~(isempty(rmv) || (all(mod(rmv,1)==0) && all(rmv>0) && all(rmv<=size(all_medians,1))))
            rmv=input('Enter valid point(s)');
        end
        for j=1:length(rmv)
            all_medians(rmv(j),:,idxs(i))=NaN;
        end
        
        %Points to Switch
        str2='Type in the points to switch \n';
        str3='e.g. [3,4], or [3,4; 5,6] - Note that enter switches no points \n';
        switches=input([str2 str3]);
        %Make sure entry is valid (either empty, or composed of markers)
        while ~(isempty(switches) || (all(all(mod(switches,1)==0)) && all(all(switches>0)) && all(all(switches<=size(all_medians,1)))))
            switches=input('Enter valid point(s)');
        end
        for j=1:size(switches,1)
            [ all_medians, all_medians2 ] = switch_pts(switches(j,:),idxs(i),all_medians,all_medians2);
        end
    end
    
    % Recalculate distances from red elbow to points on the hand (due to above changes)
    if ~isempty(idxs) %Only redo if there was a change above
        for i=1:n_times
            dists1(i)=pdist2(all_medians(10,:,i),all_medians(1,:,i));
            dists2(i)=pdist2(all_medians(10,:,i),all_medians(2,:,i));
            dists3(i)=pdist2(all_medians(10,:,i),all_medians(3,:,i));
            dists4(i)=pdist2(all_medians(10,:,i),all_medians(4,:,i));
            dists5(i)=pdist2(all_medians(10,:,i),all_medians(5,:,i));
        end
    end
    
    section_completed = 6.5;
    end
    %% Make corrections when marker 5 has a larger distance to the elbow than marker 2
    if section_completed < 6.6
    close all
    %Find times when marker 5 has a greater distance to the elbow
    %than marker 3 (which is a problem)
    idxs=find(dists5>dists2);
    
    %Plot those times
    for i=1:length(idxs)
        figure(1)
        clf
        plot_together_4colors_func(idxs(i), [2 5], [1:10], all_medians, color1, color2, color3, color4, start, finish, 1)
        title(num2str(idxs(i)));
        
        disp(['Correction block 5 of 5, correction ' num2str(i) ' out of ' num2str(length(idxs))])
        
        %Points to Remove
        str1='Pt 5 is farther from elbow than Pt 2 \n';
        str2='Type in the points to remove \n';
        str3='e.g. 1, or [1,2] - Note that enter removes no points \n';
        rmv=input([str1 str2 str3]);
        %Make sure entry is valid (either empty, or composed of markers)
        while ~(isempty(rmv) || (all(mod(rmv,1)==0) && all(rmv>0) && all(rmv<=size(all_medians,1))))
            rmv=input('Enter valid point(s)');
        end
        for j=1:length(rmv)
            all_medians(rmv(j),:,idxs(i))=NaN;
        end
        
        %Points to Switch
        str2='Type in the points to switch \n';
        str3='e.g. [3,4], or [3,4; 5,6] - Note that enter switches no points \n';
        switches=input([str2 str3]);
        %Make sure entry is valid (either empty, or composed of markers)
        while ~(isempty(switches) || (all(all(mod(switches,1)==0)) && all(all(switches>0)) && all(all(switches<=size(all_medians,1)))))
            switches=input('Enter valid point(s)');
        end
        for j=1:size(switches,1)
            [ all_medians, all_medians2 ] = switch_pts(switches(j,:),idxs(i),all_medians,all_medians2);
        end
    end
    
    
    % Recalculate distances from red elbow to points on the hand (due to above changes)
    if ~isempty(idxs) %Only redo if there was a change above
        for i=1:n_times
            dists1(i)=pdist2(all_medians(10,:,i),all_medians(1,:,i));
            dists2(i)=pdist2(all_medians(10,:,i),all_medians(2,:,i));
            dists3(i)=pdist2(all_medians(10,:,i),all_medians(3,:,i));
            dists4(i)=pdist2(all_medians(10,:,i),all_medians(4,:,i));
            dists5(i)=pdist2(all_medians(10,:,i),all_medians(5,:,i));
        end
    end

    %log file
    section_completed = 7;
    end
end

%% 8. TRACK YELLOW HAND MARKERS
if ~exist('section_completed','var') || section_completed<=8
    %% Yellow Hand (Redo)
    close all
    %Initializations
    plot_on=0;
    marker_ids=yellow_hand_marker_ids;
    color=color4;
    prev_meds=marker_inits(marker_ids,:);
    num_clust=length(marker_ids);
    within_clust_dist1=.07;
    dist_min=0.07;
    
    medians=NaN(num_clust,3,n_times);
    medians2=NaN(num_clust,3,n_times);
    
    num_gone=0; %The number of frames the marker has been gone
    
    % LOOP THROUGH TIME
    t=0;
    prev_num_clust = num_clust;
    for i=start:finish
        
        t=t+1;
        
        %0. Get x,y,z positions
        [x,y,z] = getXYZfromKinect(color{i});
        loc=[x; y; z]';
        
        if ~isempty(loc)
            %1. Filter some bad points (those that are really far away)
            %Get distances of all points to the marker in the previous frame
            if t==1
                D=pdist2(loc,prev_meds);
            else
                D=pdist2(loc,medians2(:,:,t-1));
            end

            % Keep all the points close enough to the previous marker
            keep1=D(:,1)<within_clust_dist1;

            %Remove points that are too close or far from the red elbow marker
            D2=pdist2(loc,all_medians(10,:,t));
            rmv0=D2<yellow_hand_dists_elbow(1) | D2>yellow_hand_dists_elbow(2);

            %Remove points that are too close or far from the blue arm marker
            D3=pdist2(loc,all_medians(7,:,t));
            rmv1=D3<yellow_hand_dists_bluearm(1) | D3>yellow_hand_dists_bluearm(2);

            %Remove points that are too close or far from the red arm marker
            D4=pdist2(loc,all_medians(8,:,t));
            rmv2=D4<yellow_hand_dists_redarm(1) | D4>yellow_hand_dists_redarm(2);

            rmv3=D2>dists1(t); %Points are farther from elbow than marker1
            rmv4=D2>dists2(t); %Points are farther from elbow than marker2
            rmv5=D2>dists2(t); %Points are farther from elbow than marker3

            %Use above criteria to set points for removal
            %We will always remove points that are too close or far from the arm markers (rmv0, rmv1, rmv2).
            %If the marker has been missing for <=4 frames, keep points close
            %enough to the marker's location in the previous frame
            if num_gone<=4
                rmv=~(keep1)| rmv0 | rmv1 | rmv2 |rmv3 |rmv4 |rmv5;
            else
                %If the marker has been missing for >4 frames, don't keep any points
                %based on distance to the marker's location in the previous frame
                rmv=rmv0 | rmv1 | rmv2;
            end

            %Actually remove
            loc(rmv,:)=[];
        end
        
        %2. Cluster and assign
        [ prev_num_clust, prev_meds, medians, medians2  ] = cluster_func2(t, loc, num_clust, prev_num_clust, dist_min, prev_meds, medians, medians2 );
        
        
        %Update how many frames markers have been missing
        %If the marker is missing, add 1 to num_gone. Otherwise set num_gone=0
        %(since it's been missing 0 frames)
        if isnan(medians(1,1,t))
            num_gone=num_gone+1;
        else
            num_gone=0;
        end
        
        
        %3. Plot original image and cluster centers
        plot_clusts( plot_on, num_clust, x, y, z, medians, i, t, pause_time, xlims, ylims, zlims )
        
    end
    
    all_medians(marker_ids,:,:)=medians;
    all_medians2(marker_ids,:,:)=medians2;

    %log file
    section_completed = 8;
end

%% 9. DO SOME ADDITIONAL HAND CORRECTIONS (FOR TIMES WHEN ARM MARKERS WERE MISSING)
if ~exist('section_completed','var') || section_completed<=9
    %SINCE ALL THE ABOVE WAS BASED ON DISTANCE TO THE RED ELBOW)
    if section_completed < 8.1
    %% Remove marker 3 that is too far away from other hand markers - Automatic
    close all
    %Calculate distance from marker 3 to other hand markers
    for i=1:n_times
        dists4(i)=pdist2(all_medians(3,:,i),all_medians(4,:,i)); %Distance between marker 3 and marker 4...
        dists5(i)=pdist2(all_medians(3,:,i),all_medians(5,:,i));
        dists2(i)=pdist2(all_medians(3,:,i),all_medians(2,:,i));
    end
    
    %Plot
    % if first_time
    %     figure;
    %     hold on;
    %     plot(dists4,'-x')
    %     plot(dists5,'-x')
    %     plot(dists2,'-x')
    % end
    
    %Determine frames when each of the distances is greater than expected
    d2=dists2>nanmean(dists2)+.02;
    d4=dists4>nanmean(dists4)+.02;
    d5=dists5>nanmean(dists5)+.02;
    
    %Remove when distance from all points is too large (including times when
    %marker 2 is missing)
    rmv3=(d4 & d5 & isnan(dists2)) | (d4 & d5 & d2);
    all_medians(3,:,rmv3)=NaN;
    
    section_completed = 8.1;
    end
    
    %% Remove marker 2 that is too far away from other hand markers - Automatic
    if section_completed <8.2
    close all
    %Calculate distance from marker 2 to other hand markers
    for i=1:n_times
        dists3(i)=pdist2(all_medians(2,:,i),all_medians(3,:,i)); %Distances from marker 2 to 3...
        dists4(i)=pdist2(all_medians(2,:,i),all_medians(4,:,i));
        dists5(i)=pdist2(all_medians(2,:,i),all_medians(5,:,i));
    end
    
    %Plot
    % if first_time
    %     figure;
    %     hold on;
    %     plot(dists3,'-x')
    %     plot(dists4,'-x')
    %     plot(dists5,'-x')
    % end
    
    %Determine frames when each of the distances is greater than expected
    d3=dists3>nanmean(dists3)+.03;
    d4=dists4>nanmean(dists4)+.03;
    d5=dists5>nanmean(dists5)+.03;
    
    %Remove when distance from all points is too large (including times when
    %marker 3 is missing)
    rmv2=(d4 & d5 & isnan(dists3)) | (d4 & d5 & d3);
    all_medians(2,:,rmv2)=NaN;
    
    section_completed = 8.2;
    end
    %% Set distance limits of hand markers to shoulder (after plotting the distances first), and remove markers outside those limits
    
    %Initialize some vectors that I use later for calculating the distance
    %between points
    if section_completed < 8.3
    dists1=NaN(1,n_times);
    dists2=NaN(1,n_times);
    dists3=NaN(1,n_times);
    dists4=NaN(1,n_times);
    dists5=NaN(1,n_times);
    
    %Calculate the distances from marker 9 (green shoulder) to all the hand
    %points. Note that all_medians2 is used for marker 9, since the marker will
    %not move significantly across frames, and will allow us to have a value
    %for every frame.
    for i=1:n_times
        dists1(i)=pdist2(all_medians2(9,:,i),all_medians(1,:,i));
        dists2(i)=pdist2(all_medians2(9,:,i),all_medians(2,:,i));
        dists3(i)=pdist2(all_medians2(9,:,i),all_medians(3,:,i));
        dists4(i)=pdist2(all_medians2(9,:,i),all_medians(4,:,i));
        dists5(i)=pdist2(all_medians2(9,:,i),all_medians(5,:,i));
    end
    
    close all
    
    
    if first_time
        
        if use_defaults %If you use the defaults
            
            %Get the distances at the times you include (specified when setting
            %distances to red elbow marker)
            dists1=dists1(times_inc);
            dists2=dists2(times_inc);
            dists3=dists2(times_inc);
            dists4=dists2(times_inc);
            dists5=dists2(times_inc);
            
            green_keep=[nanmean(dists5)-6*nanstd(dists5) nanmean(dists1)+6*nanstd(dists1)];
            red_keep=[nanmean(dists3)-6*nanstd(dists3) nanmean(dists3)+6*nanstd(dists3)];
            blue_keep=[nanmean(dists2)-6*nanstd(dists2) nanmean(dists2)+6*nanstd(dists2)];
            yellow_keep=[nanmean(dists4)-6*nanstd(dists4) nanmean(dists4)+6*nanstd(dists4)];
            
        else %If you don't use the defaults
            
            %Plot
            figure; % Yellow
            plot(dists4,'y-x');
            figure; %Blue
            plot(dists2,'b-x');
            figure; %Red
            plot(dists3,'r-x');
            figure; %Green
            plot(dists1,'g-x');
            hold on;
            plot(dists5,'c-x');
            
            
            % Enter hand distance limits from the shoulder
            
            str1='Input green_keep \n';
            str2='Lower and upper limits of distances of the green hand markers (green and cyan above) to the green shoulder marker\n';
            str3='Value is generally ~ [.15,.45] \n';
            green_keep=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(green_keep)==2)
                green_keep=input('Re-enter valid values');
            end
            
            str1='Input red_keep \n';
            str2='Lower and upper limits of distances of the red hand markers (red above) to the green shoulder marker\n';
            str3='Value is generally ~ [.15,.45] \n';
            red_keep=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(red_keep)==2)
                red_keep=input('Re-enter valid values');
            end
            
            str1='Input blue_keep \n';
            str2='Lower and upper limits of distances of the blue hand markers (blue above) to the green shoulder marker\n';
            str3='Value is generally ~ [.15,.45] \n';
            blue_keep=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(blue_keep)==2)
                blue_keep=input('Re-enter valid values');
            end
            
            str1='Input yellow_keep \n';
            str2='Lower and upper limits of distances of the yellow hand markers (yellow above) to the green shoulder marker\n';
            str3='Value is generally ~ [.15,.45] \n';
            yellow_keep=input([str1 str2 str3]);
            %Make sure entry was valid
            while ~(length(yellow_keep)==2)
                yellow_keep=input('Re-enter valid values');
            end
        end
    end
    
    
    % Remove hand points (because they're too close or far from shoulder)
    rmv1=dists1<green_keep(1) | dists1>green_keep(2);
    all_medians(1,:,rmv1)=NaN;
    rmv2=dists2<blue_keep(1) | dists2>blue_keep(2);
    all_medians(2,:,rmv2)=NaN;
    rmv3=dists3<red_keep(1) | dists3>red_keep(2);
    all_medians(3,:,rmv3)=NaN;
    rmv4=dists4<yellow_keep(1) | dists4>yellow_keep(2);
    all_medians(4,:,rmv4)=NaN;
    rmv5=dists5<green_keep(1) | dists5>green_keep(2);
    all_medians(5,:,rmv5)=NaN;

    %log file
    section_completed = 9;
    end
end

%% 10. CLEAN UP DATA A LITTLE, AND SAVE
if ~exist('section_completed','var') || section_completed<=10
    %% Update all_medians2 to deal with removals
    
    %If the marker is present at a given time, set all_medians2=all_medians
    %If the marker isn't present at a given time, set all_medians 2 as
    %all_medians from the previous frame
    if section_completed < 9.1
    close all
    for j=1:10 %Loop through markers
        for t=1:n_times %Loop through times
            if ~isnan(all_medians(j,1,t))
                all_medians2(j,:,t)=all_medians(j,:,t);
            else
                if t<2
                    all_medians(j,:,t)=NaN;
                else
                    all_medians2(j,:,t)=all_medians2(j,:,t-1);
                end
            end
        end
    end
    
    section_completed = 9.1;
    end
    %% Make matrices line up correctly with start time
    
    %Make the final matrices begin at time 1 instead of time "start."
    if section_completed < 9.2
    temp=all_medians;
    temp2=all_medians2;
    
    all_medians=NaN(11,3,finish);
    all_medians2=NaN(11,3,finish);
    
    all_medians(:,:,start:finish)=temp;
    all_medians2(:,:,start:finish)=temp2;

    %log file
    section_completed = 10;
    end
end

catch ME
    % if there's an error, we want to save current workspace and point user
    % to line of error
    warning('Error occured. Saving workspace (including error information in variable ME) so user can run script section by section if desired')
%     save('error_workspace.mat','-v7.3')
end

% NOW SAVING MARKERS OUTSIDE THIS SCRIPT
