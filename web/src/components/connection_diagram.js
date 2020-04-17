import React from 'react'
import PropTypes from 'prop-types'
import ChordDiagram from 'react-chord-diagram'

class ConnectionDiagram extends React.Component {
  prepareData (data) {
    const labels = []
    const assoc = {}
    const strippedLabels = []
    // Extract the labels and create a hash table for each pair
    data.forEach(elt => {
      if (!labels.includes(elt[0][0])) {
        labels.push(elt[0][0])
      }
      if (!labels.includes(elt[0][1])) {
        labels.push(elt[0][1])
      }
      assoc[[elt[0][0], elt[0][1]].sort()] = elt[1]
    })
    // Build the matrix from the labels and the hash table
    const matrix = []
    var line
    labels.forEach(a => {
      line = []
      labels.forEach(b => {
        if (a === b) {
          line.push(0)
        } else {
          const key = [a, b].sort()
          if (key in assoc) {
            line.push(assoc[key])
          } else {
            line.push(0)
          }
        }
      })
      matrix.push(line)
    })
    labels.forEach(label => {
      strippedLabels.push(label.substring(0, 12) + '...')
    })
    return { matrix: matrix, labels: strippedLabels }
  }

  render () {
    const data = this.prepareData(this.props.data)
    const graphStyle = {
      font: '50% sans-serif'
    }
    return <ChordDiagram
      matrix={data.matrix}
      componentId={1}
      groupLabels={data.labels}
      groupColors={['#003f5c', '#374c80', '#7a5195', '#bc5090', '#ef5675', '#ff764a', '#ffa600']}
      outerRadius={270}
      innerRadius={250}
      style={graphStyle}
      resizeWithWindow={true}
    />
  }
}

ConnectionDiagram.propTypes = {
  data: PropTypes.array.isRequired
}

export default ConnectionDiagram