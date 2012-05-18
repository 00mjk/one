# -------------------------------------------------------------------------- #
# Copyright 2002-2012, OpenNebula Project Leads (OpenNebula.org)             #
#                                                                            #
# Licensed under the Apache License, Version 2.0 (the "License"); you may    #
# not use this file except in compliance with the License. You may obtain    #
# a copy of the License at                                                   #
#                                                                            #
# http://www.apache.org/licenses/LICENSE-2.0                                 #
#                                                                            #
# Unless required by applicable law or agreed to in writing, software        #
# distributed under the License is distributed on an "AS IS" BASIS,          #
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.   #
# See the License for the specific language governing permissions and        #
# limitations under the License.                                             #
#--------------------------------------------------------------------------- #


module OpenNebula

    # The Pool class represents a generic OpenNebula Pool in XML format
    # and provides the basic functionality to handle the Pool elements
    class Pool < XMLPool
        include Enumerable

    protected
        #pool:: _String_ XML name of the root element
        #element:: _String_ XML name of the Pool elements
        #client::  _Client_ represents a XML-RPC connection
        def initialize(pool,element,client)
            super(nil)

            @pool_name    = pool.upcase
            @element_name = element.upcase

            @client = client
        end

        # Default Factory Method for the Pools. The factory method returns an
        # suitable PoolElement object. Each Pool MUST implement the
        # corresponding factory method
        # element_xml:: _XML_ XML element describing the pool element
        # [return] a PoolElement object
        def factory(element_xml)
            OpenNebula::PoolElement.new(element_xml,client)
        end

        #######################################################################
        # Common XML-RPC Methods for all the Pool Types
        #######################################################################

        #Gets the pool without any filter. Host, Group and User Pools
        # xml_method:: _String_ the name of the XML-RPC method
        def info(xml_method)
            return xmlrpc_info(xml_method)
        end

        def info_all(xml_method)
            return xmlrpc_info(xml_method,INFO_ALL,-1,-1)
        end

        def info_mine(xml_method)
            return xmlrpc_info(xml_method,INFO_MINE,-1,-1)
        end

        def info_group(xml_method)
            return xmlrpc_info(xml_method,INFO_GROUP,-1,-1)
        end

        def info_filter(xml_method, who, start_id, end_id)
            return xmlrpc_info(xml_method,who, start_id, end_id)
        end


        # TODO
        def monitoring(xml_method, root_elem, timestamp_elem, xpath_expressions,
            *args)

            rc = @client.call(xml_method, *args)

            if ( OpenNebula.is_error?(rc) )
                return rc
            end

            xmldoc = XMLElement.new
            xmldoc.initialize_xml(rc, 'MONITORING_DATA')

            hash = {}

            # Get all existing Object IDs
            ids = xmldoc.retrieve_elements("#{root_elem}/ID")

            if ids.nil?
                xpath_expressions.each { |xpath_expression|
                    hash[xpath_expression] = []
                }

                return hash
            else
                ids.uniq!
            end

            # Each object may have different monitorization times. This
            # method will find out the min & max values and create equally
            # spaced times for the X axis
            timestamps = equally_spaced_times(xmldoc, root_elem, timestamp_elem)


            # Get the timestamps for each individual object
            object_times_hash = {}
            ids.each { |id|
                times = xmldoc.retrieve_elements(
                    "#{root_elem}[ID=#{id}]/#{timestamp_elem}")

                times.collect!{ |i| 
                    i.to_i
                }

                object_times_hash[id] = times
            }


            xpath_expressions.each { |xpath_expression|
                hash[xpath_expression] = []

                timestamps.each { |timestamp|
                    value = nil

                    ids.each { |id|
                        xpath = "#{root_elem}[ID=#{id}]/#{xpath_expression}"

                        xpath_values = xmldoc.retrieve_elements(xpath)

                        if xpath_values.nil?
                            next
                        end

                        obj_times = object_times_hash[id]

                        # Find two points next to the timestamp we need
                        index_left  = obj_times.index{|i| i <= timestamp}
                        index_right = obj_times.index{|i| i >= timestamp}

                        if index_left.nil? || index_right.nil?
                            next
                        end

                        if index_left == index_right
                            y = xpath_values[index_left].to_i
                        else
                            # The point we need is (x,y) = (timestamp, y)
                            # X axis is obj_times, Y is xpath_values
                            y = linear_equation(
                                obj_times[index_left],          # x1
                                xpath_values[index_left].to_i,  # y1
                                obj_times[index_right],         # x2
                                xpath_values[index_right].to_i, # y2
                                timestamp)                      # known x
                        end

                        if value.nil?
                            value = y
                        else
                            # TODO: Allow other operations, sum, average, etc.
                            value += y
                        end
                    }

                    if !value.nil?
                        hash[xpath_expression] << [timestamp, value]
                    end
                }
            }

            return hash
        end


    private
        # Calls to the corresponding info method to retreive the pool
        # representation in XML format
        # xml_method:: _String_ the name of the XML-RPC method
        # args:: _Array_ with additional arguments for the info call
        # [return] nil in case of success or an Error object
        def xmlrpc_info(xml_method,*args)
            rc = @client.call(xml_method,*args)

            if !OpenNebula.is_error?(rc)
                initialize_xml(rc,@pool_name)
                rc   = nil
            end

            return rc
        end

        # Solves for y, given two known points and x
        def linear_equation(x1, y1, x2, y2, x)
            m = (y2 - y1) / (x2 - y2)
            return m * (x - x1) + y1
        end

        # Tries to guess the monitoring interval and creates equally-spaced timestamps
        def equally_spaced_times(xmldoc, root_elem, timestamp_elem)
            timestamps = xmldoc.retrieve_elements(
                "#{root_elem}/#{timestamp_elem}").collect{|i| i.to_i }

            # Get min & max time values
            t_min = timestamps.min
            t_max = timestamps.max

            id_1 = xmldoc["#{root_elem}[1]/ID"]

            elem_1_timestamps = xmldoc.retrieve_elements(
                "#{root_elem}[ID=#{id_1}]/#{timestamp_elem}")

            # TODO: try other IDs if elem_1_timestamps < 2

            monitoring_interval = elem_1_timestamps[-1].to_i - elem_1_timestamps[-2].to_i

            timestamps = []

            time = t_min
            timestamps << time
            ((t_max - t_min) / monitoring_interval).times { |i|
                timestamps << time += monitoring_interval
            }

            return timestamps
        end

    public
        # Constants for info queries (include/RequestManagerPoolInfoFilter.h)
        INFO_GROUP = -1
        INFO_ALL   = -2
        INFO_MINE  = -3

        # Iterates over every PoolElement in the Pool and calls the block with a
        # a PoolElement obtained calling the factory method
        # block:: _Block_
        def each(&block)
            each_element(block) if @xml
        end

        # DO NOT USE - ONLY REXML BACKEND
        def to_str
            str = ""
            REXML::Formatters::Pretty.new(1).write(@xml,str)

            return str
        end
    end

    # The PoolElement Class represents a generic element of a Pool in
    # XML format
    class PoolElement < XMLElement

    protected
        # node:: _XML_is a XML element that represents the Pool element
        # client:: _Client_ represents a XML-RPC connection
        def initialize(node, client)
            @xml    = node
            @client = client

            if self['ID']
                @pe_id = self['ID'].to_i
            else
                @pe_id = nil
            end
            @name = self['NAME'] if self['NAME']
        end

        #######################################################################
        # Common XML-RPC Methods for all the Pool Element Types
        #######################################################################

        # Calls to the corresponding info method to retreive the element
        # detailed information in XML format
        # xml_method:: _String_ the name of the XML-RPC method
        # root_element:: _String_ Base XML element
        # [return] nil in case of success or an Error object
        def info(xml_method, root_element)
            return Error.new('ID not defined') if !@pe_id

            rc = @client.call(xml_method,@pe_id)

            if !OpenNebula.is_error?(rc)
                initialize_xml(rc, root_element)
                rc   = nil

                @pe_id = self['ID'].to_i if self['ID']
                @name  = self['NAME'] if self['NAME']
            end

            return rc
        end

        # Calls to the corresponding allocate method to create a new element
        # in the OpenNebula core
        # xml_method:: _String_ the name of the XML-RPC method
        # args:: _Array_ additional arguments including the template for the
        #                new element
        # [return] nil in case of success or an Error object
        def allocate(xml_method, *args)
            rc = @client.call(xml_method, *args)

            if !OpenNebula.is_error?(rc)
                @pe_id = rc
                rc     = nil
            end

            return rc
        end

        # Calls to the corresponding update method to modify
        # the object's template
        # xml_method:: _String_ the name of the XML-RPC method
        # new_template:: _String_ the new template contents
        # [return] nil in case of success or an Error object
        def update(xml_method, new_template)
            return Error.new('ID not defined') if !@pe_id

            new_template ||= template_xml

            rc = @client.call(xml_method,@pe_id, new_template)
            rc = nil if !OpenNebula.is_error?(rc)

            return rc
        end

        # Calls to the corresponding delete method to remove this element
        # from the OpenNebula core
        # xml_method:: _String_ the name of the XML-RPC method
        # [return] nil in case of success or an Error object
        def delete(xml_method)
            return Error.new('ID not defined') if !@pe_id

            rc = @client.call(xml_method,@pe_id)
            rc = nil if !OpenNebula.is_error?(rc)

            return rc
        end

        # Calls to the corresponding chown method to modify
        # the object's owner and group
        # xml_method:: _String_ the name of the XML-RPC method
        # uid:: _Integer_ the new owner id. Set to -1 to leave the current one
        # gid:: _Integer_ the new group id. Set to -1 to leave the current one
        # [return] nil in case of success or an Error object
        def chown(xml_method, uid, gid)
            return Error.new('ID not defined') if !@pe_id

            rc = @client.call(xml_method,@pe_id, uid, gid)
            rc = nil if !OpenNebula.is_error?(rc)

            return rc
        end

        # Calls to the corresponding chmod method to modify
        # the object's permission bits
        #
        # @param xml_method [String] the name of the XML-RPC method
        # @param octet [String] Permissions octed , e.g. 640
        # @return [nil, OpenNebula::Error] nil in case of success, Error
        #   otherwise
        def chmod_octet(xml_method, octet)
            owner_u = octet[0..0].to_i & 4 != 0 ? 1 : 0
            owner_m = octet[0..0].to_i & 2 != 0 ? 1 : 0
            owner_a = octet[0..0].to_i & 1 != 0 ? 1 : 0
            group_u = octet[1..1].to_i & 4 != 0 ? 1 : 0
            group_m = octet[1..1].to_i & 2 != 0 ? 1 : 0
            group_a = octet[1..1].to_i & 1 != 0 ? 1 : 0
            other_u = octet[2..2].to_i & 4 != 0 ? 1 : 0
            other_m = octet[2..2].to_i & 2 != 0 ? 1 : 0
            other_a = octet[2..2].to_i & 1 != 0 ? 1 : 0

            chmod(owner_u, owner_m, owner_a, group_u, group_m, group_a, other_u,
                other_m, other_a)
        end

        # Calls to the corresponding chmod method to modify
        # the object's permission bits
        # Each [Integer] parameter must be 1 to allow, 0 deny, -1 do not change
        #
        # @param xml_method [String] the name of the XML-RPC method
        # @return [nil, OpenNebula::Error] nil in case of success, Error
        #   otherwise
        def chmod(xml_method, owner_u, owner_m, owner_a, group_u, group_m, group_a, other_u,
                other_m, other_a)
            return Error.new('ID not defined') if !@pe_id

            rc = @client.call(xml_method, @pe_id, owner_u, owner_m,
                            owner_a, group_u, group_m, group_a, other_u,
                            other_m, other_a)
            rc = nil if !OpenNebula.is_error?(rc)

            return rc
        end


        # Retrieves this Element's monitoring data from OpenNebula
        #
        # @param xml_method [String] the name of the XML-RPC method
        # @param root_elem [String] Root for each individual PoolElement

# TODO
        # @param timestamp_elem


        # @param xpath_expressions [Array<String>] Xpath expressions for the
        #   elements to retrieve.
        #
        # @return [Hash<String, Array<Array<int>>, OpenNebula::Error] Hash with
        #   the requested xpath expressions, and an Array of [timestamp, value].
        def monitoring(xml_method, root_elem, timestamp_elem, xpath_expressions)
            return Error.new('ID not defined') if !@pe_id

            rc = @client.call(xml_method, @pe_id)

            if ( OpenNebula.is_error?(rc) )
                return rc
            end

            xmldoc = XMLElement.new
            xmldoc.initialize_xml(rc, 'MONITORING_DATA')

            hash = {}
            timestamps = xmldoc.retrieve_elements(
                "#{root_elem}/#{timestamp_elem}")

            xpath_expressions.each { |xpath|
                xpath_values = xmldoc.retrieve_elements("#{root_elem}/#{xpath}")

                if ( xpath_values.nil? )
                    hash[xpath] = []
                else
                    hash[xpath] = timestamps.zip(xpath_values)
                end
            }

            return hash
        end

    public

        # Creates new element specifying its id
        # id:: identifyier of the element
        # client:: initialized OpenNebula::Client object
        def self.new_with_id(id, client=nil)
            self.new(self.build_xml(id), client)
        end

        # Returns element identifier
        # [return] _Integer_ the PoolElement ID
        def id
            @pe_id
        end

        # Gets element name
        # [return] _String_ the PoolElement name
        def name
            @name
        end

        # DO NOT USE - ONLY REXML BACKEND
        def to_str
            str = ""
            REXML::Formatters::Pretty.new(1).write(@xml,str)

            return str
        end
    end
end
