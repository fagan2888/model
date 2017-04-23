%% model.m
% an elegant MATLAB class to design, view, fit and manipulate models
% 


classdef (Abstract) model < handle

	properties (Abstract) 
		% parameters
		parameter_names
		 
		lb
		ub

		variable_names
		
	

	end % end properties

	properties

		solvers = {'ode23t','ode45','euler'};
		solver = {'euler'};
		live_update = false;

		parameters

		% data
		time
		stimulus
		response
		prediction
		plotFunctions

		
		handles 

	end


	methods

		function m = model(m)
			init(m);
			checkBounds(m);
		end

		function [m] = init(m)
			for i = 1:length(m.parameter_names)
				if m.lb(i) > 0 && m.ub(i) > 0
					m.parameters.(m.parameter_names{i}) = sqrt(m.lb(i)*m.ub(i));
				else
					m.parameters.(m.parameter_names{i}) = (m.ub(i) + m.lb(i))/2;
				end
			end


			% populate the plot functions
			all_methods =  methods(m);
			custom_plot_functions = all_methods(~cellfun(@isempty,cellfun(@(x) strfind(x,'plot'), all_methods,'UniformOutput',false)));
			m.plotFunctions = custom_plot_functions(:); %; {'plotTimeSeries','plotR_vs_S'}'];

		end % end init

		function m = checkBounds(m)
			assert(~any(m.lb >= m.ub),'At least one lower bound is greater than a upper bound')
			assert(min(((struct2mat(m.parameters) > m.lb) & (struct2mat(m.parameters) <= m.ub))),'At least one parameter out of bounds')
		end


		function m = set.stimulus(m,value)
			m.stimulus = value;
			% setting the stimulus reset the response
			m.response = [];
		end % end set stimulus


		function m = set.response(m,value)
			% force the stimulus to be set first 
			if isempty(value)
				% we're reseting it, so it's cool
				m.response = value;
			else
				assert(~isempty(m.stimulus),'Stimulus needs to be set first')
				assert(size(m.stimulus,2) == size(value,2),'Stimulus and response must be the same size')
				assert(size(m.stimulus,1) == size(value,1),'Stimulus and response must be the same size')
				m.response = value;

			end
		end % end set stimulus




		function [m] = evaluate(m)
		end % end evaluate 

		function [m] = manipulate(m)
			% check if a manipualte control window is already open. otherwise, create it
			make_gui = true;
			if ~isempty(m.handles)
				if isvalid(m.handles.manipulate_control)
					make_gui = false;
				end
			end

			if make_gui
				Height = 440;
				m.handles.manipulate_control = figure('position',[1000 250 400 Height], 'Toolbar','none','Menubar','none','NumberTitle','off','IntegerHandle','off','CloseRequestFcn',@m.quitManipulateCallback,'Name',['manipulate[' class(m) ']']);

				% draw for the first time
				f = m.parameter_names;
				pvec = struct2mat(m.parameters);

				% make sure the bounds are OK
				checkBounds(m)
		
				nspacing = Height/(length(f)+1);
				for i = 1:length(f)
					m.handles.control(i) = uicontrol(m.handles.manipulate_control,'Position',[70 Height-i*nspacing 230 20],'Style', 'slider','FontSize',12,'Callback',@m.sliderCallback,'Min',m.lb(i),'Max',m.ub(i),'Value',pvec(i));
					if m.live_update
						try    % R2013b and older
						   addlistener(m.handles.control(i),'ActionEvent',@m.sliderCallback);
						catch  % R2014a and newer
						   addlistener(m.handles.control(i),'ContinuousValueChange',@m.sliderCallback);
						end
					end
					% hat tip: http://undocumentedmatlab.com/blog/continuous-slider-callback

					thisstring = [f{i} '=',mat2str(m.parameters.(m.parameter_names{i}))];
					m.handles.controllabel(i) = uicontrol(m.handles.manipulate_control,'Position',[10 Height-i*nspacing 50 20],'style','text','String',thisstring);
					m.handles.lbcontrol(i) = uicontrol(m.handles.manipulate_control,'Position',[300 Height-i*nspacing+3 40 20],'style','edit','String',mat2str(m.lb(i)),'Callback',@m.resetSliderBounds);
					m.handles.ubcontrol(i) = uicontrol(m.handles.manipulate_control,'Position',[350 Height-i*nspacing+3 40 20],'style','edit','String',mat2str(m.ub(i)),'Callback',@m.resetSliderBounds);
				end

				% also add a pop-up menu with the different plot functions 
				m.handles.choose_plot = uicontrol(m.handles.manipulate_control,'Position',[60 10 300 20],'style','popupmenu','String',m.plotFunctions,'Callback',@m.redrawPlotFigs);

			end % end if make-gui

		end % end manipulate 

		function m = redrawPlotFigs(m,src,event)
			
			% figure out which plot function we want, and call that 
			plot_to_make = src.String(src.Value);
			% check if this method exists
			all_methods = methods(m);
			assert(~isempty(find(strcmp(plot_to_make, all_methods))),'I do not know how to make this plot. You need to write a method to make this plot and name it beginning with "plot"')

			% is there already a plot window? if so, nuke it
			if isfield(m.handles,'plot_fig')
				delete(m.handles.plot_fig)
				rmfield(m.handles,'plot_fig');
				try
					rmfield(m.handles,'plot_ax');
				catch
				end
			end

			% create the plot window by calling the appopriate function  
			m.(plot_to_make{1});
		end

		function m = plotTimeSeries(m,action)
			if ~isfield(m.handles,'plot_fig')
				% this is being called for the first time
				% create a figure
				m.handles.plot_fig = figure('position',[50 250 900 740],'NumberTitle','off','IntegerHandle','off','Name','Manipulate.m','CloseRequestFcn',@m.quitManipulateCallback);

				% make as many subplots as we have outputs + 1 for the stimulus
				nplots = length(m.variable_names) + 1;

				for i = 1:nplots - 1
					m.handles.plot_ax(i) = autoPlot(nplots,i,true); 
					hold(m.handles.plot_ax(i),'on')

					% on each plot, create handles to as many plots as there are trials in the stimulus 
					for j = 1:size(m.stimulus,2)
						m.handles.plot_data(i).handles(j) = plot(NaN,NaN);
					end

				end
				prettyFig();
				
			end
				
			if nargin == 2
				if strcmp(action,'update')
					% update X and Y data for plot handles directily from the prediction
					for i = 1:length(m.variable_names)
						for j = 1:size(m.stimulus,2)
							m.handles.plot_data(i).handles(j).XData = m.time;
							m.handles.plot_data(i).handles(j).YData = m.prediction.(m.variable_names{i})(:,j);
						end
					end
				end
			end



		end

		function m = sliderCallback(m,src,~)
			this_param = find(m.handles.control == src);
			m.parameters.(m.parameter_names{this_param}) = src.Value;

			% update the values shown in text 
			m.handles.controllabel(this_param).String = [m.parameter_names{this_param} '=',mat2str(m.parameters.(m.parameter_names{this_param}))];

			% evaluate the model 
			m.evaluate;

			% nudge the chosen plot function to update plots
			plot_to_make = m.handles.choose_plot.String{(m.handles.choose_plot.Value)};
			m.(plot_to_make)('update');

		end % end sliderCallback


		function m = checkStringNum(m,value)
			assert(~isnan(str2double(value)),'Enter a real number')
		end % end checkStringNum

		function m = resetSliderBounds(m,src,~)
			checkStringNum(m,src.String);
			if any(m.handles.lbcontrol == src)
				% some lower bound being changed
				this_param = find(m.handles.lbcontrol == src);
				new_bound = str2double(src.String);
				m.lb(this_param) = new_bound;
				
				if m.handles.control(this_param).Value < new_bound
					m.handles.control(this_param).Value = new_bound;
					m.parameters.(m.parameter_names{this_param}) = new_bound;
				end
				checkBounds(m)
				m.handles.control(this_param).Min = new_bound;
			elseif any(m.handles.ubcontrol == src)
				% some upper bound being changed
				this_param = find(m.handles.ubcontrol == src);
				new_bound = str2double(src.String);
				m.ub(this_param) = new_bound;
				
				if m.handles.control(this_param).Value > new_bound
					m.handles.control(this_param).Value = new_bound;
					m.parameters.(m.parameter_names{this_param}) = new_bound;
				end
				checkBounds(m)
				m.handles.control(this_param).Max = new_bound;
			else
				error('error 142')
			end
		end % end resetSliderBounds

		function [m] = quitManipulateCallback(m,~,~)
			% destroy every object in m.handles
			d = fieldnames(m.handles);
			for i = 1:length(d)
				try
					delete(m.handles.(d{i}))
				catch
				end
			end

		end % end quitManipulateCallback 

	end % end all methods
end	% end classdef

