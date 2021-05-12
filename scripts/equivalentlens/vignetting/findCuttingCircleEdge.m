function [radius,sensitivity] = findCuttingCircleEdge(points,offaxis_distances,side,offset_vertex,stepsize_radius)
%findCuttingCircleEdge Estimate the circles that cut off the entrance pupil
%
%  Algorithm works by choosing either the furthest (top or bottom) vertex
%  and finding the circle with minimal radius that encloses all points at
%  all off-axis distances. 
%  From this the radius and sensitivity (how much it moves with off axis
%  distance) can be estimated. One has to play with tolerances here and
%  there to get a satisfactory fit.
%
%
%
%  INPUTS
%      points - 2xPxN  (X,Y) x  (pupil positions)  x points
%      offaxis_distances - 1xP   radial off-axis distances
%      offset_vertex - A small offset added to the furthest vertex distance
%                      this helps with enclosing all points correctly when the pupil is not
%                       perfectly circular.  It is therefore a tuning parameter.
%      stepsize_radius - Determines the increments in radius to be tried.

%  OUTPUTS
%     - radius - Radius of the circle
%     - sensitivity - Defined as displacement_of_center =
%                      sensitivity*offaxis_distances
%
% Thomas Goossens




if(side=="bottom")
    sign=1;
    extreme =  @(x) min(x);
else %top
    sign=-1;
    extreme =  @(x) max(x);
end


stopcondition=0;

% The circles have to be at least larger than the entrance pupil radius,
% else they would be the entrance pupil by definition.
Rest=0;
while(not(prod(stopcondition)))
    for p=1:numel(offaxis_distances)
        Ptrace=points(1:2,p,:);
        
        NaNCols = any(isnan(Ptrace)); % Ignore untraced rays (NAN)
        Pnan = Ptrace(:,~NaNCols);
        ZeroCols = any(Pnan(:,:)==[0;0]); % ingore rays through center (PATCH FOR UNSOLVED BUG)
        Pnan = Pnan(:,~ZeroCols);
        
        % Step 1: choose lowest point
        y_extreme = extreme(Pnan(2,:))-sign*offset_vertex;
        
        stopcondition(p)=sum((sum((Pnan-[0;(y_extreme+sign*Rest)]).^2,1)<=Rest^2)==0)<1;        
    end
    Rest = Rest+stepsize_radius;


end

radius = Rest;
ycenter=y_extreme+sign*radius;
sensitivity=ycenter/offaxis_distances(p);




end

