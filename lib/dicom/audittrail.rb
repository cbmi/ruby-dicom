module DICOM
    class AuditTrail

        def initialize(filename="audittrail.json")
            @filename = filename
            audittrail = File.new(@filename, "r")
    
            # if the file is not empty, load the JSON, if not, just create an empty hash
            if audittrail.size > 0
                @dictionary = JSON.load(audittrail)
            else
                @dictionary = Hash.new
            end
            audittrail.close
        end
        
        def add_tag_record(tagname, orignal, clean, date=nil)
            @dictionary[tagname] = Hash.new if not @dictionary[tagname]
            @dictionary[tagname][original] = clean
        end
    
        def get_clean_tag(tagname, original)
            lowercase = tagname.downcase
            return @dictionary[lowercase][original] if @dictionary.has_key(lowercase)
        end
        
        def serialize
            audittrail = File.new(@filename, "w")
            JSON.dump(@dictionary, anIO=audittrail)
            audittrail.close
        end

        def previous_values(tagname)
            return 0 if not @dictionary[tagname]
            return @dictionary[tagname].size
        end
    
    end
end
