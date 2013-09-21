#!/usr/bin/env ruby -wKU
require "awesome_print"
Movie = Struct.new :movie_id, :rate
@users_data = {}
File.open("recsys_data_ratings.csv", "r") do |file|
  data = file.readlines
  file.close
  data.each do |data_line|
    data_line.chomp!
    split_info = data_line.split ','
    movie = Movie.new
    user_id, movie.movie_id, movie.rate = split_info[0], split_info[1], split_info[2].to_f
    @users_data[user_id] ||= []
    @users_data[user_id].push movie
  end
end

DEFAULT = { count: 0, rate: 0 }
MOVIE1 = "77"
MOVIE2 = "550"
MOVIE3 = "1597"
# MOVIE1 = "11"
# MOVIE2 = "121"
# MOVIE3 = "8587"
# contiene el diccionario de las peliculas que estamos analizando
# con su contador de veces que fueron vistas y la suma de cada calificacion
@movies_dict = Hash.new { |hash, key| hash[key] = DEFAULT.clone }
@movies_dict.instance_eval do
  def add_to movie
    self[movie[:name]][:count] += 1
    self[movie[:name]][:rate] += movie[:rate]
  end

  # si la pelicula es una de las peliculas sobre las que estamos
  # recomendando agregamos la calificacion encontrada, de lo
  # contrario retornamos falso pues no es una de las que estamos
  # analizando
  def fill movie
    case movie.movie_id
    when MOVIE1
      add_to name: MOVIE1, rate: movie.rate
    when MOVIE2
      add_to name: MOVIE2, rate: movie.rate
    when MOVIE3
      add_to name: MOVIE3, rate: movie.rate
    else
      false
    end
  end

  # personas que vieron (X y Y) / personas que vieron X
  # calcula la relacion directa ente X&Y
  def calculate_relation relation
    movie1 = relation[:with]
    times_both_selected = relation[:times]
    times_both_selected.fdiv( self[movie1][:count] )
  end

  # personas que vieron (X y Y) / personas que vieron X
  # eso dividido con las personas que no vieron X pero si
  # vieron Y / personas totales - las personas que no vieron X
  # (X&Y)/X / (!X&Y)/!X
  # osea calcular la relacion inderecta entre X&Y
  def calculate_relation_advance_formula relation
    movie = relation[:with]
    related_movie_score = relation[:related_movie_score]
    no_movie_times = relation[:times_no_movie]
    total_users = relation[:total_users]
    movie_times = self[movie][:count]
    no_votes_for_movie = total_users - movie_times
    related_movie_score.fdiv( no_movie_times.fdiv( no_votes_for_movie ) )
  end
end
@movies_dict[MOVIE1]
@movies_dict[MOVIE2]
@movies_dict[MOVIE3]

@movie_association = {
  MOVIE1 => {},
  MOVIE2 => {},
  MOVIE3 => {},
}
# diccionario que contiene las peliculas que estan relacionadas con alguna
# varias o todas las peliculas que estamos analizando, y su rescpectivo contador 
# de las veces que cada pelicula se ha relacionado directamente con la pelicula
# analizada
@movie_association.instance_eval do
  def add_association association
    movie = association[:to]
    with_movie = association[:with]
    self[movie][with_movie.movie_id] ||= 0
    self[movie][with_movie.movie_id] += 1
  end
end

@movie_no_association = {
  MOVIE1 => {},
  MOVIE2 => {},
  MOVIE3 => {}
}
# diccionario que contiene las peliculas que no estan relacionadas con alguna
# pelicula de las que estamos analizando, y un contador de las veces que cada
# pelicula no se ha relacionado directamente con la pelicula analizada
@movie_no_association.instance_eval do
  def add_no_association no_association
    movie, with_movie = no_association[:between]
    self[movie][with_movie.movie_id] ||= 0
    self[movie][with_movie.movie_id] += 1
  end
end

class Array
  # en el mismo arreglo busco si hay alguna pelicula con el id
  # que recive como parametro, si no la hay retorna nil
  def has_movie? movie_id
    self.index {|movie| movie.movie_id == movie_id}
  end

  # recivo como parametro un porcentage de relacion entre 2 peliculas
  # luego itero sobre el arreglo que contiene las peliculas con los mayores
  # porcentages de relacion donde las posiciones pares son los id de las 
  # peliculas y las posiciones impares son los porcentages de relacion
  # por lo que si la posicion es par continuo con la siguiente iteracion
  # mientras itero busco el elemento con el porcentage mas bajo y cojo
  # su posicion luego elimino su id por lo que su posicion baja en una unidad
  # luego elimino esa posicion donde que quedo, si no hay un porcentage mas
  # bajo que el nuevo retorno falso indicando que no se efectuo ninguna operacion
  def change_with? score
    change_index = nil
    temp = score
    self.each.with_index do |movie_selected, index|
      next unless index.odd?
      if movie_selected < temp
        temp = movie_selected
        change_index = index
      end
    end
    if change_index
      self.delete_at change_index - 1
      self.delete_at change_index - 1
    else
      false
    end
  end
end

@users_data.each do |user, user_movies|
  user_movies.each do |movie|
    # intenta ver la pelicula vista por el usuario es una de las que busco recomendar,
    # si lo es agrega los datos correspondientes, de lo contrario entra a agregar relaciones
    # conlas demas peliculas o anti-relaciones
    unless @movies_dict.fill movie
      # usuarios que vieron X&Y de lo contrario es porque solo vieron Y y no X por lo que es !X&Y
      # user see movie1 and movieY else just Y and not X
      if user_movies.has_movie? MOVIE1 then @movie_association.add_association to: MOVIE1, with: movie
      else @movie_no_association.add_no_association between: [MOVIE1, movie] end
        # user see movie2 and movieY else just Y and not X
      if user_movies.has_movie? MOVIE2 then @movie_association.add_association to: MOVIE2, with: movie
      else @movie_no_association.add_no_association between: [MOVIE2, movie] end
        # user see movie3 and movieY else just Y and not X
      if user_movies.has_movie? MOVIE3 then @movie_association.add_association to: MOVIE3, with: movie
      else @movie_no_association.add_no_association between: [MOVIE3, movie] end
    end
  end
end

# awesome_print @movie_association
@result = {}
# (x and y)/x
# X&Y/X
# calcula el porcentage de relacion entre las peliculas para poderlas recomendar
# movie => String
# movies_associated_with => Hash
# movie_name => String, alias de movie_id
# movie_count => Numeric, numero de veces que X tubo relacion con Y
@movie_association.each do |movie, movies_associated_with|
  selected = []
  movies_associated_with.each do |movie_name, movie_count|
    # calcula el porcentage de relacion entre X&Y sobre X
    score = @movies_dict.calculate_relation with: movie, times: movie_count
    # si el arreglo de los mas relacionados llega a las 10 posciones entonces
    # empieza a buscar el menor porcentage de relacion, si lo encuentra lo
    # elimina dejando espacio para agregar al nuevo, de lo contrario sigue iterando
    if selected.size == 10
      if selected.change_with? score
        selected.push movie_name
        selected.push score
      end
    else
       selected.push movie_name
       selected.push score
    end
    end
  @result[movie] = selected
end

@advance_result = {}
# (!x and y)/!x
# (X&Y/X) / (!X&Y/!X)
# calcula el porcentage de relacion entre las peliculas para poderlas recomendar basado
# en la relacion directa sobre la relacion inderecta para tener datos estadisticos mucho
# mas precisos
# movie => String
# movies_no_associated_with => Hash
# movie_name => String, alias de movie_id
# times => Numeric, numero de veces que X no tubo relacion con Y, osea las veces que
# votaron por Y pero no por X
@movie_no_association.each do |movie, movies_no_associated_with|
  selected = []
  movies_no_associated_with.each do |movie_name, times|
    # calcular la relacion directa entre X&Y/X
    times_both_selected = @movie_association[movie][movie_name]
    related_movie_score = @movies_dict.calculate_relation with: movie, times: times_both_selected
    # calcular la relacion inderecta entre X&Y con la formula (X&Y/X) / (!X&Y/!X)
    no_relation_score = @movies_dict.calculate_relation_advance_formula(
      with: movie,
      times_no_movie: times,
      total_users: @users_data.size,
      related_movie_score: related_movie_score
    )
    if selected.size == 10
      if selected.change_with? no_relation_score
        selected.push movie_name
        selected.push no_relation_score
      end
    else
       selected.push movie_name
       selected.push no_relation_score
    end
  end
  @advance_result[movie] = selected
end
# awesome_print @result
# imprimir en un documento csv el resultado de la recomendacion
writer = Proc.new do | path, dictionary|
  File.open(path, "w") do |file|
    dictionary.each do |movie, selected|
      file.print "#{movie}"
      selected.each_slice 2 do |movie_id, score|
        file.print ",#{movie_id},#{score}"
      end
      file.puts
    end
  end
end

writer.call "simple.csv", @result
writer.call "advance.csv", @advance_result
