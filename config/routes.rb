# frozen_string_literal: true

# The pages and their REST resources (.json) are the same routes; GET on ceilings, private and strict_counts is REST
# only (the page shows them on Administration > Levels). The fixed paths stand before the resources, so that they are
# never read as a level's id.
scope 'gk_access' do
  get 'levels/ceilings', to: 'gk_access_levels#ceilings_show', as: 'gk_access_level_ceilings_show'
  post 'levels/ceilings', to: 'gk_access_levels#ceilings', as: 'gk_access_level_ceilings'
  put 'levels/ceilings', to: 'gk_access_levels#ceilings'
  get 'levels/private', to: 'gk_access_levels#private_show', as: 'gk_access_level_private_show'
  post 'levels/private', to: 'gk_access_levels#private_mode', as: 'gk_access_level_private'
  put 'levels/private', to: 'gk_access_levels#private_mode'
  get 'levels/strict_counts', to: 'gk_access_levels#strict_counts', as: 'gk_access_level_strict_counts'
  resources :levels, controller: 'gk_access_levels', as: 'gk_access_levels'
end
get 'projects/:project_id/gk_access/private', to: 'gk_access_private_modes#show', as: 'gk_access_project_private_show'
post 'projects/:project_id/gk_access/private', to: 'gk_access_private_modes#update', as: 'gk_access_project_private'
put 'projects/:project_id/gk_access/private', to: 'gk_access_private_modes#update'
