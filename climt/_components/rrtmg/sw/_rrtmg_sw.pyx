cimport numpy as cnp
import numpy as np
cimport cython
from cython.parallel import prange


#Flags
cdef cnp.int32_t rrtm_cloud_overlap_method
cdef cnp.int32_t rrtm_cloud_props_flag
cdef cnp.int32_t rrtm_ice_props_flag
cdef cnp.int32_t rrtm_liq_droplet_flag
cdef cnp.int32_t rrtm_aerosol_input_flag
cdef cnp.int32_t rrtm_solar_variability_flag
cdef double rrtm_solar_constant
cdef double [:]  rrtm_fac_sunspot_ampl
cdef double [:]  rrtm_solar_var_by_band

#Definitions of the functions we want to use within
#CliMT: initialisation and radiative transfer
cdef extern:
    void rrtmg_shortwave_init(double *cp_d_air)

cdef extern:
    void rrtmg_set_constants(double *pi, double *grav, double *planck,
                            double *boltz, double *clight, double *avogadro,
                            double *loschmidt, double *gas_const,
                            double *stef_boltz, double *secs_per_day)

cdef extern nogil:
    void rrtmg_shortwave(
        cnp.int32_t *num_cols, cnp.int32_t *num_layers,
        cnp.int32_t *cld_overlap_method, cnp.int32_t *aerosol_input_format,
        double *layer_pressure, double *interface_pressure,
        double *layer_temp, double *interface_temp, double *surface_temp,
        double *h2o_vmr, double *o3_vmr, double *co2_vmr,
        double *ch4_vmr, double *n2o_vmr, double *o2_vmr,
        double *surface_direct_sw_albedo, double *surface_direct_nir_albedo,
        double *surface_diffuse_sw_albedo, double *surface_diffuse_nir_albedo,
        double *cosine_zenith_angle, double *flux_adj_earth_sun_dist,
        cnp.int32_t *day_of_year, double *solar_constant,
        cnp.int32_t *solar_variability_type,
        cnp.int32_t *cloud_props_flag, cnp.int32_t *ice_props_flag,
        cnp.int32_t *liq_droplet_flag, double *cloud_fraction,
        double *cloud_tau, double *cloud_single_scat_albedo,
        double *cloud_asym, double *cloud_fwd_scat_frac,
        double *cloud_ice_path, double *cloud_liq_path,
        double *cloud_ice_eff_size, double *cloud_droplet_eff_radius, double *aerosol_tau,
        double *aer_single_scat_albedo, double *aer_asym,
        double *aer_tau_at_55_micron,
        double *upward_shortwave_flux, double *downward_shortwave_flux,
        double *shortwave_heating_rate, double *up_sw_flux_clearsky,
        double *down_sw_flux_clearsky, double *sw_heating_rate_clearsky,
        double *sol_var_scale_factors, double *fac_sunspot_ampl,
        double *solar_cycle_frac)


#Use random cloud overlap model as default.
def initialise_rrtm_radiation(
    double cp_d_air,
    double solar_constant,
    cnp.ndarray[cnp.double_t, ndim=1] facular_sunspot_ampl,
    cnp.ndarray[cnp.double_t, ndim=1] solar_var_banded,
    cnp.int32_t cloud_overlap_method=1,
    cnp.int32_t cloud_props_flag=0,
    cnp.int32_t ice_props_flag=0,
    cnp.int32_t liq_droplet_flag=0,
    cnp.int32_t aerosol_input_flag=0,
    cnp.int32_t solar_var_flag=0):

    rrtmg_shortwave_init(&cp_d_air)

    global rrtm_cloud_overlap_method, rrtm_cloud_props_flag,\
        rrtm_ice_props_flag, rrtm_liq_droplet_flag,\
        rrtm_aerosol_input_flag, rrtm_solar_variability_flag,\
        rrtm_solar_constant, rrtm_fac_sunspot_ampl,\
        rrtm_solar_var_by_band

    rrtm_cloud_overlap_method = cloud_overlap_method
    rrtm_cloud_props_flag = cloud_props_flag
    rrtm_ice_props_flag = ice_props_flag
    rrtm_liq_droplet_flag = liq_droplet_flag
    rrtm_aerosol_input_flag = aerosol_input_flag
    rrtm_solar_variability_flag = solar_var_flag
    rrtm_solar_constant = solar_constant
    rrtm_fac_sunspot_ampl = facular_sunspot_ampl
    rrtm_solar_var_by_band = solar_var_banded

def set_constants(double pi, double grav, double planck, double boltz,
                  double clight, double avogadro, double loschmidt, double gas_const,
                  double stef_boltz, double secs_per_day):

    rrtmg_set_constants(&pi, &grav, &planck,
                        &boltz, &clight, &avogadro,
                        &loschmidt, &gas_const,
                        &stef_boltz, &secs_per_day)

@cython.boundscheck(False)
cpdef void rrtm_calculate_shortwave_fluxes(
    cnp.int32_t num_lons,
    cnp.int32_t num_lats,
    cnp.int32_t num_layers,
    cnp.int32_t day_of_year,
    double solar_cycle_fraction,
    double flux_adj_sun_earth,
    cnp.double_t[::1,:,:] layer_pressure,
    cnp.double_t[::1,:,:] interface_pressure,
    cnp.double_t[::1,:,:] layer_temp,
    cnp.double_t[::1,:,:] interface_temp,
    cnp.double_t[::1,:] surface_temp,
    cnp.double_t[::1,:,:] h2o_vmr,
    cnp.double_t[::1,:,:] o3_vmr,
    cnp.double_t[::1,:,:] co2_vmr,
    cnp.double_t[::1,:,:] ch4_vmr,
    cnp.double_t[::1,:,:] n2o_vmr,
    cnp.double_t[::1,:,:] o2_vmr,
    cnp.double_t[::1,:] sfc_direct_sw_albedo,
    cnp.double_t[::1,:] sfc_direct_nir_albedo,
    cnp.double_t[::1,:] sfc_diffuse_sw_albedo,
    cnp.double_t[::1,:] sfc_diffuse_nir_albedo,
    cnp.double_t[::1,:] cos_zenith_angle,
    cnp.double_t[::1,:,:] cloud_fraction,
    cnp.double_t[::1,:,:] upward_shortwave_flux,
    cnp.double_t[::1,:,:] downward_shortwave_flux,
    cnp.double_t[::1,:,:] shortwave_heating_rate,
    cnp.double_t[::1,:,:] up_sw_flux_clearsky,
    cnp.double_t[::1,:,:] down_sw_flux_clearsky,
    cnp.double_t[::1,:,:] sw_heating_rate_clearsky,
    cnp.double_t[::1,:,:,:] aerosol_tau,
    cnp.double_t[::1,:,:,:] aerosol_single_scat_alb,
    cnp.double_t[::1,:,:,:] aerosol_asym,
    cnp.double_t[::1,:,:,:] aerosol_at_55u,
    cnp.double_t[::1,:,:,:] cloud_tau,
    cnp.double_t[::1,:,:,:] cloud_single_scat_alb,
    cnp.double_t[::1,:,:,:] cloud_asym,
    cnp.double_t[::1,:,:,:] cloud_fwd_scat_frac,
    cnp.double_t[::1,:,:] cloud_ice_path,
    cnp.double_t[::1,:,:] cloud_liq_path,
    cnp.double_t[::1,:,:] cloud_ice_eff_size,
    cnp.double_t[::1,:,:] cloud_droplet_eff_radius):

    global rrtm_cloud_overlap_method, rrtm_cloud_props_flag,\
        rrtm_ice_props_flag, rrtm_liq_droplet_flag,\
        rrtm_aerosol_input_flag, rrtm_solar_variability_flag,\
        rrtm_solar_constant, rrtm_fac_sunspot_ampl,\
        rrtm_solar_var_by_band

    cdef cnp.int32_t num_cols = 1
    cdef int lon, lat, latlon

    with nogil:
        for latlon in prange(num_lats*num_lons, schedule=dynamic):
                lon = latlon/num_lats
                lat = latlon%num_lats
                rrtmg_shortwave(
                    &num_cols, &num_layers,
                    &rrtm_cloud_overlap_method,
                    &rrtm_aerosol_input_flag,
                    <double *>&layer_pressure[0,lat,lon],
                    <double *>&interface_pressure[0,lat,lon],
                    <double *>&layer_temp[0,lat,lon],
                    <double *>&interface_temp[0,lat,lon],
                    <double *>&surface_temp[lat,lon],
                    <double *>&h2o_vmr[0,lat,lon],
                    <double *>&o3_vmr[0,lat,lon],
                    <double *>&co2_vmr[0,lat,lon],
                    <double *>&ch4_vmr[0,lat,lon],
                    <double *>&n2o_vmr[0,lat,lon],
                    <double *>&o2_vmr[0,lat,lon],
                    <double *>&sfc_direct_sw_albedo[lat,lon],
                    <double *>&sfc_diffuse_sw_albedo[lat,lon],
                    <double *>&sfc_direct_nir_albedo[lat,lon],
                    <double *>&sfc_diffuse_nir_albedo[lat,lon],
                    <double *>&cos_zenith_angle[lat,lon],
                    &flux_adj_sun_earth,
                    &day_of_year,
                    &rrtm_solar_constant,
                    &rrtm_solar_variability_flag,
                    &rrtm_cloud_props_flag,
                    &rrtm_ice_props_flag,
                    &rrtm_liq_droplet_flag,
                    <double *>&cloud_fraction[0,lat,lon],
                    <double *>&cloud_tau[0,lat,0,lon],
                    <double *>&cloud_single_scat_alb[0,lat,0,lon],
                    <double *>&cloud_asym[0,lat,0,lon],
                    <double *>&cloud_fwd_scat_frac[0,lat,0,lon],
                    <double *>&cloud_ice_path[0,lat,lon],
                    <double *>&cloud_liq_path[0,lat,lon],
                    <double *>&cloud_ice_eff_size[0,lat,lon],
                    <double *>&cloud_droplet_eff_radius[0,lat,lon],
                    <double *>&aerosol_tau[0,0,lat,lon],
                    <double *>&aerosol_single_scat_alb[0,0,lat,lon],
                    <double *>&aerosol_asym[0,0,lat,lon],
                    <double *>&aerosol_at_55u[0,0,lat,lon],
                    <double *>&upward_shortwave_flux[0,lat,lon],
                    <double *>&downward_shortwave_flux[0,lat,lon],
                    <double *>&shortwave_heating_rate[0,lat,lon],
                    <double *>&up_sw_flux_clearsky[0,lat,lon],
                    <double *>&down_sw_flux_clearsky[0,lat,lon],
                    <double *>&sw_heating_rate_clearsky[0,lat,lon],
                    <double *>&rrtm_solar_var_by_band[0],
                    <double *>&rrtm_fac_sunspot_ampl[0],
                &solar_cycle_fraction)

#    return (upward_shortwave_flux, downward_shortwave_flux,
#            shortwave_heating_rate, up_sw_flux_clearsky,
#            down_sw_flux_clearsky, sw_heating_rate_clearsky)
