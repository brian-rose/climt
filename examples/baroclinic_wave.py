import climt
from sympl import PlotFunctionMonitor


def plot_function(fig, state):

    ax = fig.add_subplot(1, 1, 1)
    state['surface_air_pressure'].to_units('mbar').transpose().plot.contourf(
        ax=ax, levels=16)
    ax.set_title('Surface Pressure at: '+str(state['time']))


monitor = PlotFunctionMonitor(plot_function)

climt.set_constant('reference_air_pressure', value=1e5, units='Pa')
dycore = climt.GFSDynamicalCore(number_of_longitudes=198,
                                number_of_latitudes=94)
dcmip = climt.DcmipInitialConditions()

my_state = climt.get_default_state([dycore], x=dycore.grid_definition['x'],
                                   y=dycore.grid_definition['y'],
                                   mid_levels=dycore.grid_definition['mid_levels'],
                                   interface_levels=dycore.grid_definition['interface_levels'])

my_state['surface_air_pressure'].values[:] = 1e5
dycore(my_state)

out = dcmip(my_state, add_perturbation=True)

my_state.update(out)

for i in range(1000):
    output, diag = dycore(my_state)
    monitor.store(my_state)
    my_state.update(output)
    my_state['time'] += dycore._time_step
