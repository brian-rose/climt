import climt
from sympl import PlotFunctionMonitor, NetCDFMonitor
import numpy as np
from metpy import calc
from metpy.units import units
import matplotlib.pyplot as plt


def plot_function(fig, state):

    ax = fig.add_subplot(2, 2, 1)
    state['surface_temperature'].transpose().plot.contourf(ax=ax, levels=16)
    ax.set_title('Surf. Temperature')

    ax = fig.add_subplot(2, 2, 3)
    state['eastward_wind'].mean(dim='longitude').transpose().plot.contourf(
        ax=ax, levels=16, robust=True)
    ax.set_title('Zonal Wind')

    ax = fig.add_subplot(2, 2, 2)
    state['shortwave_heating_rate'].mean(
        dim='longitude').transpose().plot.contourf(
        ax=ax, levels=16, robust=True)
    ax.set_title('SW. Heating Rate')

    ax = fig.add_subplot(2, 2, 4)
    state['air_temperature'].mean(dim='longitude').transpose().plot.contourf(
        ax=ax, levels=16)
    ax.set_title('Temperature')

    plt.suptitle('Time: '+str(state['time']))
    fig.tight_layout(rect=[0, 0.03, 1, 0.95])


fields_to_store = list(climt.RRTMGShortwave._climt_inputs) + list(
    climt.RRTMGShortwave._climt_tendencies) + list(
        climt.RRTMGShortwave._climt_diagnostics)
# Create plotting object
monitor = PlotFunctionMonitor(plot_function)
netcdf_monitor = NetCDFMonitor('gcm_output.nc', write_on_store=True,
                               store_names=fields_to_store)

climt.set_constants_from_dict({
    'stellar_irradiance': {'value': 200, 'units': 'W m^-2'}})

# Create components
dycore = climt.GFSDynamicalCore(number_of_longitudes=128,
                                number_of_latitudes=62,
                                number_of_damped_levels=5,
                                time_step=1200.)

model_time_step = dycore._time_step

convection = climt.EmanuelConvection(
    convective_momentum_transfer_coefficient=1)
simple_physics = climt.SimplePhysics()

simple_physics = simple_physics.prognostic_version()
simple_physics.current_time_step = model_time_step
convection.current_time_step = model_time_step

# run radiation once every hour
constant_duration = 3

radiation_lw = climt.RRTMGLongwave()
radiation_lw = radiation_lw.piecewise_constant_version(
    constant_duration*model_time_step)

radiation_sw = climt.RRTMGShortwave(use_solar_constant_from_fortran=False)
radiation_sw = radiation_sw.piecewise_constant_version(
    constant_duration*model_time_step)

slab_surface = climt.SlabSurface()

# Create model state
my_state = climt.get_default_state([dycore, radiation_lw, radiation_sw,
                                    convection,
                                    simple_physics, slab_surface],
                                   x=dycore.grid_definition['x'],
                                   y=dycore.grid_definition['y'],
                                   mid_levels=dycore.grid_definition[
                                       'mid_levels'],
                                   interface_levels=dycore.grid_definition[
                                       'interface_levels'])

# Set initial/boundary conditions
latitudes = my_state['latitude'].values

zenith_angle = np.radians(latitudes)

my_state['zenith_angle'].values[:] = zenith_angle[np.newaxis, :]

my_state['eastward_wind'].values[:] = np.random.randn(
    *my_state['eastward_wind'].shape)
my_state['ocean_mixed_layer_thickness'].values[:] = 50

surf_temp_profile = 290 - (40*np.sin(zenith_angle)**2)
my_state['surface_temperature'].values[:] = surf_temp_profile[np.newaxis, :]

surf_temp = 280*units.degK
pressure = my_state['air_pressure'][0, 0, :].values*units.pascal
temp_profile = np.array(calc.moist_lapse(pressure, surf_temp))
temp_profile[-5::] = temp_profile[-5]
my_state['air_temperature'].values[:] = temp_profile[
    np.newaxis, np.newaxis, :]


dycore.prognostics = [simple_physics, slab_surface, radiation_sw,
                      radiation_lw, convection]

for i in range(500000):
    output, diag = dycore(my_state)
    my_state.update(output)
    my_state.update(diag)
    my_state['time'] += model_time_step

    print('All q values are positive: ',
          np.all(my_state['specific_humidity'] >= 0))

    if i % 3 == 0:
        monitor.store(my_state)

    # Output once evey half day
    if i % 18 == 0:
        netcdf_monitor.store(my_state)

    print('max. zonal wind: ',
          np.amax(my_state['eastward_wind'].values))
    print('max. surf temp: ',
          my_state['surface_temperature'].max(keep_attrs=True).values)
