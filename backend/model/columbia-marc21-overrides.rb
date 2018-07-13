class MARCModel < ASpaceExport::ExportModel
  model_for :marc21

  include JSONModel

	#don't export empty fields when using df_handler
	def self.df_handler(name, tag, ind1, ind2, code)
		define_method(name) do |val|
			if val
				df(tag, ind1, ind2).with_sfs([code, val])
			end
		end
		name.to_sym
	end

  @resource_map = {
    [:id_0, :id_1, :id_2, :id_3] => :handle_id,
    :notes => :handle_notes,
		:user_defined => :handle_user_defined,
    :finding_aid_description_rules => df_handler('fadr', '040', ' ', ' ', 'e'),
    :finding_aid_note => df_handler('fan', '555', '0', ' ', 'a'),
    :ead_location => :handle_ead_loc
  }

	#Picked from new release, but added 035
	def df(*args)
    if @datafields.has_key?(args.to_s)
      # Manny Rodriguez: 3/16/18
      # Bugfix for ANW-146
      # Separate creators should go in multiple 700 fields in the output MARCXML file. This is not happening because the different 700 fields are getting mashed in under the same key in the hash below, instead of having a new hash entry created.
      # So, we'll get around that by using a different hash key if the code is 700.
      # based on MARCModel#datafields, it looks like the hash keys are thrown away outside of this class, so we can use anything as a key.
      # At the moment, we don't want to change this behavior too much in case something somewhere else is relying on the original behavior.

     if(args[0] == "700" || args[0] == "710" || args[0] == "035")
       @datafields[rand(10000)] = @@datafield.new(*args)
     else 
       @datafields[args.to_s]
     end
    else

      @datafields[args.to_s] = @@datafield.new(*args)
      @datafields[args.to_s]
    end
  end

	#Add an 035 based on string + id0
  def handle_id(*ids)
    ids.reject!{|i| i.nil? || i.empty?}
    df('099', ' ', ' ').with_sfs(['a', ids.join('.')])
    df('852', ' ', ' ').with_sfs(['c', ids.join('.')])
		last035 = 'CULASPC-' + ids[0]
		df('035', ' ', ' ').with_sfs(['a', last035])
  end

	#Don't export language to random 04x fields
	#Should be fixed upstream soon
  def handle_language(langcode)
    df('041', '0', ' ').with_sfs(['a', langcode])
  end

	def handle_user_defined(user_defined)
    return false if user_defined.nil?
		df('852', ' ', ' ').with_sfs(['j', user_defined['string_1']])
		df('035', ' ', ' ').with_sfs(['a', user_defined['string_2']])
		df('035', ' ', ' ').with_sfs(['a', user_defined['string_3']])
		df('035', ' ', ' ').with_sfs(['a', user_defined['string_4']])
	end

	#Remove 555 from ead_loc export, we're doing it above with fa note
  def handle_ead_loc(ead_loc)
    df('856', '4', '2').with_sfs(
                                ['z', "Finding aid online:"],
                                ['u', ead_loc]
                                ) if ead_loc
  end



end  
